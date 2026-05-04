{ lib }:

let
  graph = import ./graph.nix { inherit lib; };
  helpers = import ./static-helpers.nix { inherit lib; };
  overlayCoreSelection = import ./overlay-core-selection.nix { inherit lib; };

  uplinkRouteEntriesFromNode =
    node:
    let
      ifs = node.interfaces or { };
      ifNames = builtins.attrNames ifs;

      perIface =
        ifName:
        let
          rs = helpers.ifaceRoutes ifs.${ifName};
        in
        (map (r: {
          family = 4;
          dst = r.dst or null;
        }) (lib.filter (r: (r.proto or null) == "uplink" && (r ? dst)) rs.ipv4))
        ++ (map (r: {
          family = 6;
          dst = r.dst or null;
        }) (lib.filter (r: (r.proto or null) == "uplink" && (r ? dst)) rs.ipv6));
    in
    lib.concatMap perIface ifNames;

in
{
  addToSelector =
    {
      topo,
      nodeName,
      node,
      nextHopWithPreferredUplinks,
      mkRoute4,
      mkRoute6,
    }:
    let
      selectorNode = topo.upstreamSelectorNodeName or null;
      uplinkCores = helpers.uplinkCores topo;
      routeExportCores = overlayCoreSelection.nonOverlayUplinkCores topo uplinkCores;
      ownSet = helpers.ownConnectedPrefixes (topo.nodes.${nodeName});

      advertised = lib.concatMap (
        core:
        let
          coreNode = topo.nodes.${core} or { };
          path = graph.shortestPath {
            links = topo.links or { };
            src = nodeName;
            dst = core;
          };
        in
        if path == null || builtins.length path < 2 then
          [ ]
        else
          let
            hop = builtins.elemAt path 1;
            nextHop = nextHopWithPreferredUplinks {
              inherit topo;
              from = nodeName;
              to = hop;
              preferredUplinks = topo.uplinkNames or [ ];
            };

            exported = lib.filter (e: e.dst != null && !(ownSet ? "${toString e.family}|${e.dst}")) (
              uplinkRouteEntriesFromNode coreNode
            );
          in
          if nextHop.linkName == null then
            [ ]
          else
            map (
              e:
              e
              // {
                linkName = nextHop.linkName;
                via4 = if e.family == 4 then nextHop.via4 else null;
                via6 = if e.family == 6 then nextHop.via6 else null;
              }
            ) exported
      ) routeExportCores;

      usable = lib.filter (
        e: (e.family == 4 && e.via4 != null) || (e.family == 6 && e.via6 != null)
      ) advertised;

      perLink = builtins.foldl' (
        acc: e:
        let
          add4 =
            if e.family == 4 then
              [
                (mkRoute4 {
                  dst = e.dst;
                  via4 = e.via4;
                  proto = "uplink";
                  intentKind = "uplink-learned-reachability";
                })
              ]
            else
              [ ];

          add6 =
            if e.family == 6 then
              [
                (mkRoute6 {
                  dst = e.dst;
                  via6 = e.via6;
                  proto = "uplink";
                  intentKind = "uplink-learned-reachability";
                })
              ]
            else
              [ ];
        in
        acc
        // {
          "${e.linkName}" = {
            routes4 = helpers.dedupeRoutes ((acc.${e.linkName}.routes4 or [ ]) ++ add4);
            routes6 = helpers.dedupeRoutes ((acc.${e.linkName}.routes6 or [ ]) ++ add6);
          };
        }
      ) { } usable;

      linkNames = builtins.attrNames perLink;
    in
    if selectorNode == null || nodeName != selectorNode then
      node
    else
      builtins.foldl' (
        acc: linkName:
        let
          add = perLink.${linkName};
        in
        helpers.addRoutesOnLink acc linkName add.routes4 add.routes6
      ) node linkNames;
}
