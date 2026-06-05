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
  staticAggregates = import ./static-aggregates.nix { inherit lib; };

  routeNormalization = import ./static/route-normalization.nix {
    inherit
      canonicalCidr
      lib
      rawDedupeRoutes
      stripMask
      summarizeCidrs
      trace
      ;
    inherit (dynamicRoutes) routeUsesDynamicSource dedupeDynamicRoutes;
  };
  inherit (routeNormalization) normalizeRouteList dedupeRoutes;

  rawIfaceRoutes =
    iface:
    if iface ? routes && builtins.isAttrs iface.routes then
      {
        ipv4 = iface.routes.ipv4 or [ ];
        ipv6 = iface.routes.ipv6 or [ ];
      }
    else
      {
        ipv4 = iface.routes4 or [ ];
        ipv6 = iface.routes6 or [ ];
      };

  withoutPreserveDst = map (route: builtins.removeAttrs route [ "preserveDst" ]);

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

  addRoutesOnLinkFromMaterializedRoutes =
    node: linkName: add4: add6:
    let
      ifs = node.interfaces or { };
      cur = ifs.${linkName} or { };
      curRoutes = rawIfaceRoutes cur;
    in
    node
    // {
      interfaces = ifs // {
        "${linkName}" = cur // {
          routes = {
            ipv4 = normalizeRouteList 4 ((withoutPreserveDst curRoutes.ipv4) ++ add4);
            ipv6 = normalizeRouteList 6 ((withoutPreserveDst curRoutes.ipv6) ++ add6);
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
    addRoutesOnLinkFromMaterializedRoutes
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
