{ lib, self ? { outPath = ./.; }, ... }:

let
  ip = import (self.outPath + "/implementation/lib/net/ip-utils.nix") { inherit lib self; };
  prefix = import (self.outPath + "/implementation/lib/model/prefix-utils.nix") { inherit lib self; };
  routes = import (self.outPath + "/implementation/lib/model/routes.nix") { inherit lib self; };
  trace = import (self.outPath + "/lib/trace.nix") { };

  default4 = "0.0.0.0/0";
  default6 = "::/0";

  stripMask = ip.stripMask;
  canonicalCidr = prefix.canonicalCidr;
  ifaceRoutes = routes.ifaceRoutes;
  rawDedupeRoutes = routes.dedupeRoutes;

  cidrSummary = import ./cidr-summary.nix { inherit lib self; };
  summarizeCidrs = cidrSummary.summarizeCidrs;
  routeBuilders = import ./route-builders.nix { inherit lib default6 canonicalCidr; };
  inherit (routeBuilders) mkRoute4 mkRoute6;
  dynamicRoutes = import ./dynamic-routes.nix { inherit lib; };
  inherit (dynamicRoutes) routeUsesDynamicSource dedupeDynamicRoutes;
  staticAggregates = import ./static-aggregates.nix { inherit lib; };

  routeBase =
    r:
    builtins.removeAttrs r [
      "dst"
      "preserveDst"
    ];

  detectRouteFamily = r: if lib.hasInfix ":" (stripMask r.dst) then 6 else 4;

  routePreservesDst = r: (r.preserveDst or false) == true;
  normalizeRouteList =
    family: rs:
    trace.emit "routing:normalizeRouteList:${toString family}:${toString (builtins.length rs)}" (
      let
        dynamicRoutes = dedupeDynamicRoutes (lib.filter routeUsesDynamicSource rs);
        staticRoutes = lib.filter (r: !(routeUsesDynamicSource r)) rs;
        normalizedStatic =
          if staticRoutes == [ ] then
            [ ]
          else if builtins.length staticRoutes == 1 then
            let
              route = builtins.head (rawDedupeRoutes staticRoutes);
              dst =
                if routePreservesDst route then
                  route.dst
                else
                  canonicalCidr route.dst;
            in
            [ (routeBase route // { inherit dst; }) ]
          else
            let
              grouped = lib.groupBy (r: builtins.toJSON (routeBase r)) staticRoutes;

              normalizedGroups = lib.concatMap
                (
                  key:
                  let
                    group = grouped.${key};
                    base = routeBase (builtins.head group);
                    cidrs =
                      if lib.any routePreservesDst group then
                        lib.unique (map (r: r.dst) group)
                      else
                        lib.unique (map (r: canonicalCidr r.dst) group);
                    renderedCidrs =
                      if lib.any routePreservesDst group then
                        lib.sort (a: b: a < b) cidrs
                      else if
                        builtins.length cidrs <= 1
                        && !(family == 6 && builtins.match ".*/0" (builtins.head cidrs) != null)
                      then
                        cidrs
                      else
                        summarizeCidrs family cidrs;
                  in
                  map (dst: base // { dst = dst; }) renderedCidrs
                )
                (builtins.attrNames grouped);
            in
            lib.sort (a: b: (builtins.toJSON a) < (builtins.toJSON b)) normalizedGroups;
      in
      normalizedStatic ++ dynamicRoutes
    );

  dedupeRoutes =
    rs:
    let
      grouped = lib.groupBy (r: toString (detectRouteFamily r)) rs;
      v4 = if grouped ? "4" then normalizeRouteList 4 grouped."4" else [ ];
      v6 = if grouped ? "6" then normalizeRouteList 6 grouped."6" else [ ];
    in
    lib.sort (a: b: (builtins.toJSON a) < (builtins.toJSON b)) (v4 ++ v6);

  addRoutesOnLink =
    node: linkName: add4: add6:
    let
      ifs = node.interfaces or { };
      cur = ifs.${linkName} or { };
      curRoutes = ifaceRoutes cur;
    in
    node
    // {
      interfaces = ifs // {
        "${linkName}" = cur // {
          routes = {
            ipv4 = normalizeRouteList 4 (curRoutes.ipv4 ++ add4);
            ipv6 = normalizeRouteList 6 (curRoutes.ipv6 ++ add6);
          };
        };
      };
    };

  allNodeNames = topo: builtins.attrNames (topo.nodes or { });

in
{
  inherit
    default4
    default6
    stripMask
    canonicalCidr
    ifaceRoutes
    mkRoute4
    mkRoute6
    dedupeRoutes
    addRoutesOnLink
    allNodeNames
    summarizeCidrs
    normalizeRouteList
    ;
  inherit (staticAggregates)
    buildP2pAggregate
    buildTenantAggregate
    aggregationMode
    uplinkCores
    ;
  inherit (prefix)
    prefixEntriesFromIfaces
    prefixEntriesFromNetworks
    ownConnectedPrefixes
    prefixSetFromP2pIfaces
    prefixSetFromNetworks
    ;
  prefixSetFromTenantNetworks = prefix.prefixSetFromNetworks;
}
