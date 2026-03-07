{ lib }:

let
  cidr = import ../fabric/invariants/cidr-utils.nix { inherit lib; };
  ip = import ../net/ip-utils.nix { inherit lib; };
  network = import ../model/network-utils.nix { inherit lib; };

  default4 = "0.0.0.0/0";
  default6 = "::/0";

  splitCidr = ip.splitCidr;
  intToV4 = ip.intToIPv4;
  stripMask = ip.stripMask;

  canonicalCidr =
    cidrStr:
    let
      c = splitCidr cidrStr;
      r = cidr.cidrRange cidrStr;
      base = if r.family == 4 then intToV4 r.start else toString r.start;
    in
    "${base}/${toString c.prefix}";

  ifaceRoutes =
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

  mkRoute4 = dst: via4: proto: {
    dst = canonicalCidr dst;
    inherit via4 proto;
  };

  mkRoute6 = dst: via6: proto: {
    dst = canonicalCidr dst;
    inherit via6 proto;
  };

  routeKey =
    r:
    "${toString (r.dst or "")}|${toString (r.via4 or "")}|${toString (r.via6 or "")}|${toString (r.proto or "")}";

  dedupeRoutes =
    routes0:
    builtins.attrValues (builtins.foldl' (acc: r: acc // { "${routeKey r}" = r; }) { } routes0);

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
            ipv4 = dedupeRoutes (curRoutes.ipv4 ++ add4);
            ipv6 = dedupeRoutes (curRoutes.ipv6 ++ add6);
          };
        };
      };
    };

  networksOf = network.networksOfNode { };

  allNodeNames = topo: builtins.attrNames (topo.nodes or { });

  prefixEntriesFromIfaces =
    node:
    let
      ifs = node.interfaces or { };
      ifNames = builtins.attrNames ifs;
    in
    lib.concatMap (
      ifName:
      let
        iface = ifs.${ifName};
      in
      lib.flatten [
        (lib.optional (iface ? addr4 && iface.addr4 != null) {
          family = 4;
          dst = canonicalCidr iface.addr4;
        })
        (lib.optional (iface ? addr6 && iface.addr6 != null) {
          family = 6;
          dst = canonicalCidr iface.addr6;
        })
        (lib.optional (iface ? addr6Public && iface.addr6Public != null) {
          family = 6;
          dst = canonicalCidr iface.addr6Public;
        })
        (map (p: {
          family = 6;
          dst = canonicalCidr p;
        }) (iface.ra6Prefixes or [ ]))
      ]
    ) ifNames;

  prefixEntriesFromNetworks =
    node:
    let
      nets = networksOf node;
      netNames = builtins.attrNames nets;
    in
    lib.concatMap (
      netName:
      let
        net = nets.${netName};
      in
      lib.flatten [
        (lib.optional (net ? ipv4 && net.ipv4 != null) {
          family = 4;
          dst = canonicalCidr net.ipv4;
        })
        (lib.optional (net ? ipv6 && net.ipv6 != null) {
          family = 6;
          dst = canonicalCidr net.ipv6;
        })
      ]
    ) netNames;

  ownConnectedPrefixes =
    node:
    builtins.foldl' (acc: e: acc // { "${toString e.family}|${e.dst}" = true; }) { } (
      prefixEntriesFromIfaces node ++ prefixEntriesFromNetworks node
    );

  prefixSetFromP2pIfaces =
    node:
    let
      ifs = node.interfaces or { };
      ifNames = builtins.attrNames ifs;
    in
    builtins.foldl' (
      acc: ifName:
      let
        iface = ifs.${ifName};
      in
      if (iface.kind or null) != "p2p" then
        acc
      else
        acc
        // (lib.optionalAttrs (iface ? addr4 && iface.addr4 != null) {
          "4|${canonicalCidr iface.addr4}" = {
            family = 4;
            dst = canonicalCidr iface.addr4;
          };
        })
        // (lib.optionalAttrs (iface ? addr6 && iface.addr6 != null) {
          "6|${canonicalCidr iface.addr6}" = {
            family = 6;
            dst = canonicalCidr iface.addr6;
          };
        })
    ) { } ifNames;

  prefixSetFromTenantNetworks =
    node:
    let
      nets = networksOf node;
      netNames = builtins.attrNames nets;
    in
    builtins.foldl' (
      acc: netName:
      let
        net = nets.${netName};
      in
      acc
      // (lib.optionalAttrs (net ? ipv4 && net.ipv4 != null) {
        "4|${canonicalCidr net.ipv4}" = {
          family = 4;
          dst = canonicalCidr net.ipv4;
        };
      })
      // (lib.optionalAttrs (net ? ipv6 && net.ipv6 != null) {
        "6|${canonicalCidr net.ipv6}" = {
          family = 6;
          dst = canonicalCidr net.ipv6;
        };
      })
    ) { } netNames;

  buildP2pAggregate =
    topo: family:
    let
      pool = topo.p2p-pool or { };
    in
    if family == 4 then pool.ipv4 or null else pool.ipv6 or null;

  buildTenantAggregate =
    topo: family:
    if family == 4 then
      if topo ? tenantV4Base then "${topo.tenantV4Base}.0.0/16" else null
    else if topo ? ulaPrefix then
      "${topo.ulaPrefix}::/56"
    else
      null;

  aggregationMode =
    topo:
    if topo ? aggregation && builtins.isAttrs topo.aggregation && topo.aggregation ? mode then
      topo.aggregation.mode
    else
      "none";

  uplinkCores =
    topo:
    if topo ? uplinkCoreNames && builtins.isList topo.uplinkCoreNames then
      topo.uplinkCoreNames
    else
      [ ];

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
    ownConnectedPrefixes
    prefixSetFromP2pIfaces
    prefixSetFromTenantNetworks
    buildP2pAggregate
    buildTenantAggregate
    aggregationMode
    uplinkCores
    ;
}
