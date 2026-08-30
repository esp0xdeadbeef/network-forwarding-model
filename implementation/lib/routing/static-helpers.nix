{
  lib,
  self ? {
    outPath = ./.;
  },
  ...
}:

let
  ip = import (self.outPath + "/implementation/lib/net/ip-utils.nix") { inherit lib self; };
  prefix = import (self.outPath + "/implementation/lib/model/prefix-utils.nix") { inherit lib self; };
  routes = import (self.outPath + "/implementation/lib/model/routes.nix") { inherit lib self; };
  trace = import (self.outPath + "/lib/trace.nix") { };

  default4 = "0.0.0.0/0";
  default6 = "::/0";

  # The IPv6 egress default is derived from the declared WAN uplink prefixes,
  # not hardcoded to ::/0. Routed client GUA sites declare 2::/3 (global
  # unicast) so the fabric default only attracts internet-bound GUA, while ULA,
  # link-local and multicast stay on their more-specific routes. Falls back to
  # ::/0 when no uplink declares an IPv6 prefix.
  default6For =
    nodes:
    let
      prefixLength =
        prefix:
        let
          m = builtins.match ".*/([0-9]+)$" (toString prefix);
        in
        if m == null then 128 else builtins.fromJSON (builtins.head m);
      uplinkIpv6Prefixes = builtins.concatLists (
        builtins.concatMap (
          nodeName:
          builtins.map (
            uplinkName: ((((nodes.${nodeName} or { }).uplinks or { }).${uplinkName} or { }).ipv6 or [ ])
          ) (builtins.attrNames ((nodes.${nodeName} or { }).uplinks or { }))
        ) (builtins.attrNames (if builtins.isAttrs nodes then nodes else { }))
      );
      sorted = builtins.sort (a: b: prefixLength a < prefixLength b) uplinkIpv6Prefixes;
    in
    if sorted == [ ] then default6 else builtins.head sorted;

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
            # Keep the preserveDst marker on the pre-existing routes: it is
            # what keeps /32 (and /128) host routes, such as router loopbacks,
            # from being summarized into wider prefixes when the default lanes
            # are added on top. Stripping it here re-summarized 10.1.1.8/32 +
            # 10.1.1.9/32 into 10.1.1.8/31 and erased the distinct core
            # loopback next hops.
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
        accIfs
        // {
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
    default6For
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
