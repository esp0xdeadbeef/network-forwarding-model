{ lib }:

let
  ip = import ../net/ip-utils.nix { inherit lib; };
  prefix = import ../model/prefix-utils.nix { inherit lib; };
  routes = import ../model/routes.nix { inherit lib; };

  default4 = "0.0.0.0/0";
  default6 = "::/0";

  stripMask = ip.stripMask;
  canonicalCidr = prefix.canonicalCidr;
  ifaceRoutes = routes.ifaceRoutes;
  dedupeRoutes = routes.dedupeRoutes;

  mkRoute4 = dst: via4: proto: {
    dst = canonicalCidr dst;
    inherit via4 proto;
  };

  mkRoute6 = dst: via6: proto: {
    dst = canonicalCidr dst;
    inherit via6 proto;
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
            ipv4 = dedupeRoutes (curRoutes.ipv4 ++ add4);
            ipv6 = dedupeRoutes (curRoutes.ipv6 ++ add6);
          };
        };
      };
    };

  allNodeNames = topo: builtins.attrNames (topo.nodes or { });

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
