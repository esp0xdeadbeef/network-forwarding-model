{ lib }:

{
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
        linkedUplinkCores = lib.concatMap
          (
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
          )
          linkNames;
        nodeUplinkCores =
          lib.filter
            (
              nodeName:
              let
                node = nodes.${nodeName} or { };
              in
              builtins.isAttrs (node.uplinks or null) && builtins.attrNames node.uplinks != [ ]
            )
            (builtins.attrNames nodes);
      in
      lib.sort (a: b: a < b) (lib.unique (nodeUplinkCores ++ linkedUplinkCores));
}
