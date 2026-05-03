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
  rawDedupeRoutes = routes.dedupeRoutes;

  cidrSummary = import ./cidr-summary.nix { inherit lib; };
  summarizeCidrs = cidrSummary.summarizeCidrs;

  normalizeIntent =
    x:
    if x == null then
      null
    else if builtins.isAttrs x && (x.kind or null) != null then
      x // { kind = toString x.kind; }
    else if builtins.isString x then
      { kind = toString x; }
    else
      { kind = toString x; };

  mkRoute4 =
    {
      dst,
      via4,
      proto,
      intent ? null,
      extra ? { },
      routeExtra ? { },
    }:
    {
      dst = canonicalCidr dst;
      inherit via4 proto;
    }
    // lib.optionalAttrs (normalizeIntent intent != null) {
      intent = normalizeIntent intent;
    }
    // extra
    // routeExtra;

  mkRoute6 =
    {
      dst,
      via6,
      proto,
      intent ? null,
      extra ? { },
      routeExtra ? { },
    }:
    {
      dst = canonicalCidr dst;
      inherit via6 proto;
    }
    // lib.optionalAttrs (normalizeIntent intent != null) {
      intent = normalizeIntent intent;
    }
    // extra
    // routeExtra;

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
    let
      grouped = lib.groupBy (r: builtins.toJSON (routeBase r)) (rawDedupeRoutes rs);

      normalizedGroups = lib.concatMap (
        key:
        let
          group = grouped.${key};
          base = routeBase (builtins.head group);
          cidrs = lib.unique (map (r: canonicalCidr r.dst) group);
          renderedCidrs =
            if lib.any routePreservesDst group then
              lib.sort (a: b: a < b) cidrs
            else
              summarizeCidrs family cidrs;
        in
        map (dst: base // { dst = dst; }) renderedCidrs
      ) (builtins.attrNames grouped);
    in
    lib.sort (a: b: (builtins.toJSON a) < (builtins.toJSON b)) normalizedGroups;

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
    if topo ? uplinkCoreNames && builtins.isList topo.uplinkCoreNames && topo.uplinkCoreNames != [ ] then
      topo.uplinkCoreNames
    else
      let
        nodes = topo.nodes or { };
        links = topo.links or { };
        linkNames = builtins.attrNames links;
        linkedUplinkCores = lib.concatMap (
          linkName:
          let
            link = links.${linkName};
            uplinks = link.uplinks or [ ];
            members = link.members or [ ];
          in
          if !(builtins.isList uplinks) || uplinks == [ ] || !(builtins.isList members) then
            [ ]
          else
            lib.filter (nodeName: (nodes.${nodeName}.role or null) == "core") (map toString members)
        ) linkNames;
        nodeUplinkCores =
          lib.filter (
            nodeName:
            let
              node = nodes.${nodeName} or { };
            in
            builtins.isAttrs (node.uplinks or null) && builtins.attrNames node.uplinks != [ ]
          ) (builtins.attrNames nodes);
      in
      lib.sort (a: b: a < b) (lib.unique (nodeUplinkCores ++ linkedUplinkCores));
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
    summarizeCidrs
    normalizeRouteList
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
