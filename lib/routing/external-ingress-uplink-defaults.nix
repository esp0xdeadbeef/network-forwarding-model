{ lib }:

let
  graph = import ./graph.nix { inherit lib; };
  helpers = import ./static-helpers.nix { inherit lib; };
in
{
  apply =
    {
      topo,
      nodeName,
      node,
      nextHopWithPreferredUplinks,
      mkRoute4,
      mkRoute6,
    }:
    let
      selectorNodeName = topo.upstreamSelectorNodeName or null;
      role = node.role or null;
      nodes = topo.nodes or { };
      links = topo.links or { };
      linkNames = builtins.attrNames links;
      contract = topo.communicationContract or { };
      relations =
        if builtins.isList (contract.allowedRelations or null) then
          contract.allowedRelations
        else if builtins.isList (contract.relations or null) then
          contract.relations
        else
          [ ];

      coreHasUplink =
        coreName: uplinkName:
        let
          core = nodes.${coreName} or { };
          uplinks = core.uplinks or { };
          linkHasUplink = lib.any (
            linkName:
            let
              link = links.${linkName};
              members = link.members or [ ];
              linkUplinks = link.uplinks or [ ];
            in
            builtins.isList members
            && builtins.elem coreName (map toString members)
            && builtins.isList linkUplinks
            && builtins.elem uplinkName (map toString linkUplinks)
          ) linkNames;
        in
        builtins.hasAttr uplinkName uplinks || linkHasUplink;

      coresForUplink =
        uplinkName:
        lib.filter (coreName: coreHasUplink coreName uplinkName) (helpers.uplinkCores topo);

      externalToUplinkRelations = lib.filter (
        relation:
        (relation.action or "allow") == "allow"
        && (relation.from.kind or null) == "external"
        && (relation.from.name or null) != null
        && (relation.to.kind or null) == "external"
        && builtins.isList (relation.to.uplinks or null)
        && (relation.to.uplinks or [ ]) != [ ]
      ) relations;

      firstHopTo =
        targetCore: preferredUplinks:
        let
          path = graph.shortestPath {
            inherit links;
            src = nodeName;
            dst = targetCore;
          };
        in
        if path == null || builtins.length path < 2 then
          {
            linkName = null;
            via4 = null;
            via6 = null;
          }
        else
          nextHopWithPreferredUplinks {
            inherit topo preferredUplinks;
            from = nodeName;
            to = builtins.elemAt path 1;
          };

      routesForTarget =
        targetUplinkName: targetCore:
        let
          nh = firstHopTo targetCore [ targetUplinkName ];
        in
        {
          routes4 =
            if nh.via4 == null then [ ] else [
              (mkRoute4 {
                dst = helpers.default4;
                via4 = nh.via4;
                proto = "default";
                intentKind = "default-reachability";
              })
            ];
          routes6 =
            if nh.via6 == null then [ ] else [
              (mkRoute6 {
                dst = helpers.default6;
                via6 = nh.via6;
                proto = "default";
                intentKind = "default-reachability";
              })
            ];
        };

      entries = lib.concatMap (
        relation:
        let
          sourceName = relation.from.name;
          sourceCores = coresForUplink sourceName;
          targetUplinks = relation.to.uplinks or [ ];
        in
        lib.concatMap (
          sourceCore:
          let
            sourceNh = firstHopTo sourceCore [ sourceName ];
          in
          if sourceNh.linkName == null then [ ] else
            lib.concatMap (
              targetUplinkName:
              map (targetCore: {
                linkName = sourceNh.linkName;
                routes = routesForTarget targetUplinkName targetCore;
              }) (coresForUplink targetUplinkName)
            ) targetUplinks
        ) sourceCores
      ) externalToUplinkRelations;
    in
    if selectorNodeName == null || nodeName != selectorNodeName || role != "upstream-selector" then
      node
    else
      builtins.foldl' (
        acc: entry:
        helpers.addRoutesOnLink acc entry.linkName entry.routes.routes4 entry.routes.routes6
      ) node entries;
}
