{ lib, self ? { outPath = ./.; }, ... }:

let
  graphContext = import ./graph/context.nix { inherit lib self; };
  helpers = import ./static-helpers.nix { inherit lib self; };
  directWanDefaults = import ./direct-wan-defaults.nix { inherit lib self; };
  laneDefaults = import ./lane-defaults.nix { inherit lib self; };
  overlayCoreSelection = import ./overlay-core-selection.nix { inherit lib self; };
in
{
  apply =
    { topo
    , nodeName
    , node
    , routeContext
    , routeFacts ? routeContext.buildFacts topo
    , routeGraph ? graphContext.build (topo.links or { }) { }
    ,
    }:
    let
      inherit (routeContext) nextHopWithPreferredUplinks;

      passArgs = {
        inherit
          topo
          nodeName
          node
          routeContext
          routeFacts
          ;
      };

      nearestDefaultRoute =
        family: nextHop:
        if nextHop == null then
          [ ]
        else
          [
            ((if family == 4 then routeContext.mkRoute4 else routeContext.mkRoute6) {
              dst = if family == 4 then helpers.default4 else helpers.default6;
              ${if family == 4 then "via4" else "via6"} = nextHop;
              proto = "default";
              intentKind = "default-reachability";
            })
          ];

      overlayTerminatingCores = overlayCoreSelection.overlayTerminatingCores topo;

      avoidsOverlayTransit =
        path:
        let
          len = builtins.length path;
          intermediate = if len <= 2 then [ ] else lib.sublist 1 (len - 2) path;
        in
        lib.all (node: !(builtins.elem node overlayTerminatingCores)) intermediate;

      nearestUplinkCore =
        let
          uplinks = routeFacts.uplinkCores or [ ];
          candidates = overlayCoreSelection.nonOverlayUplinkCores topo uplinks;
          reachable =
            lib.filter
              (
                target:
                let
                  path = routeGraph.shortestPath {
                    src = nodeName;
                    dst = target;
                  };
                in
                path != null && builtins.length path >= 2 && avoidsOverlayTransit path
              )
              candidates;
        in
        if uplinks == [ ] || lib.elem nodeName uplinks || reachable == [ ] then
          null
        else
          builtins.head (lib.sort (a: b: a < b) reachable);

      overlayUnderlayAccessNode =
        let
          accessNodes = overlayCoreSelection.underlayAccessNodesForCore topo nodeName;
          reachable =
            lib.filter
              (
                target:
                let
                  path = routeGraph.shortestPath {
                    src = nodeName;
                    dst = target;
                  };
                in
                path != null && builtins.length path >= 2
              )
              accessNodes;
        in
        if reachable == [ ] then null else builtins.head (lib.sort (a: b: a < b) reachable);

      nearestDefaultTarget =
        if overlayUnderlayAccessNode != null then overlayUnderlayAccessNode else nearestUplinkCore;

      overlayUplinkNameSet = routeFacts.overlayUplinkNameSet or { };
      nonOverlayUplinkNames = routeFacts.nonOverlayUplinkNames or [ ];
      defaultReachabilityUplinkNames = routeFacts.defaultReachabilityUplinkNames or (topo.uplinkNames or [ ]);

      addDefaultTowardNearestUplinkCore =
        if nearestDefaultTarget == null then
          node
        else
          let
            path = routeGraph.shortestPath {
              src = nodeName;
              dst = nearestDefaultTarget;
            };
            nextHop = nextHopWithPreferredUplinks {
              inherit topo;
              from = nodeName;
              to = builtins.elemAt path 1;
              inherit routeGraph;
              preferredUplinks = defaultReachabilityUplinkNames;
            };
            selectedLink =
              if nextHop.linkName == null then null else (topo.links or { }).${nextHop.linkName} or { };
            selectedUplinkName = routeContext.laneUplinkNameFromLink selectedLink;
            selectedIsOverlayUplink =
              selectedUplinkName != null && builtins.hasAttr selectedUplinkName overlayUplinkNameSet;
            skipOverlayGenericDefault = nonOverlayUplinkNames != [ ] && selectedIsOverlayUplink;
          in
          if nextHop.linkName == null || skipOverlayGenericDefault then
            node
          else
            helpers.addRoutesOnLink
              node
              nextHop.linkName
              (nearestDefaultRoute 4 nextHop.via4)
              (nearestDefaultRoute 6 nextHop.via6);
    in
    {
      inherit addDefaultTowardNearestUplinkCore;
      addDownstreamSelectorPolicyLaneDefaults = laneDefaults.addDownstreamSelectorPolicyDefaults passArgs;
      addPolicyUpstreamSelectorLaneDefaults = laneDefaults.addPolicyUpstreamSelectorDefaults passArgs;
      addUpstreamSelectorPolicyLaneCoreDefaults = laneDefaults.addUpstreamSelectorPolicyLaneCoreDefaults passArgs;
      addDirectWanDefaults = directWanDefaults.apply { inherit node routeContext; };
    };
}
