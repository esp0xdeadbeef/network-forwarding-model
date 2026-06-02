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

  sortRoutesByJSON =
    rs:
    map
      (entry: entry.route)
      (builtins.sort (a: b: a.key < b.key) (
        map
          (route: {
            key = builtins.toJSON route;
            inherit route;
          })
          rs
      ));

  uniqueStrings =
    xs:
    builtins.attrNames (builtins.listToAttrs (map (x: {
      name = x;
      value = true;
    }) xs));

  detectRouteFamily = r: if lib.hasInfix ":" (stripMask r.dst) then 6 else 4;

  routePreservesDst = r: (r.preserveDst or false) == true;

  normalizeRouteList =
    family: rs:
    trace.emit "routing:normalizeRouteList:${toString family}:${toString (builtins.length rs)}" (
      let
        dynamicRoutes = dedupeDynamicRoutes (builtins.filter routeUsesDynamicSource rs);
        staticRoutes = builtins.filter (r: !(routeUsesDynamicSource r)) rs;
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
              keyedRoutes = map
                (
                  r:
                  let
                    base = routeBase r;
                  in
                  {
                    inherit base;
                    key = builtins.toJSON base;
                    preserveDst = routePreservesDst r;
                    rawDst = r.dst;
                  }
                )
                staticRoutes;
              grouped = builtins.groupBy (r: r.key) keyedRoutes;

              normalizedGroups = builtins.concatMap
                (
                  key:
                  let
                    group = grouped.${key};
                    base = (builtins.head group).base;
                    preservesDst = builtins.any (r: r.preserveDst) group;
                    cidrs =
                      if preservesDst then
                        uniqueStrings (map (r: r.rawDst) group)
                      else
                        uniqueStrings (map (r: canonicalCidr r.rawDst) group);
                    renderedCidrs =
                      if preservesDst then
                        builtins.sort (a: b: a < b) cidrs
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
            sortRoutesByJSON normalizedGroups;
      in
      normalizedStatic ++ dynamicRoutes
    );

  dedupeRoutes =
    rs:
    let
      grouped = builtins.groupBy (r: toString (detectRouteFamily r)) rs;
      v4 = if grouped ? "4" then normalizeRouteList 4 grouped."4" else [ ];
      v6 = if grouped ? "6" then normalizeRouteList 6 grouped."6" else [ ];
    in
    sortRoutesByJSON (v4 ++ v6);

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

  addRoutePlan =
    node: plan:
    let
      ifs = node.interfaces or { };
      applyLink =
        accIfs: linkName:
        let
          add = plan.${linkName};
          cur = accIfs.${linkName} or { };
          curRoutes = ifaceRoutes cur;
        in
        accIfs // {
          "${linkName}" = cur // {
            routes = {
              ipv4 = normalizeRouteList 4 (curRoutes.ipv4 ++ (add.routes4 or [ ]));
              ipv6 = normalizeRouteList 6 (curRoutes.ipv6 ++ (add.routes6 or [ ]));
            };
          };
        };
    in
    node
    // {
      interfaces = builtins.foldl' applyLink ifs (builtins.attrNames plan);
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
    addRoutePlan
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
