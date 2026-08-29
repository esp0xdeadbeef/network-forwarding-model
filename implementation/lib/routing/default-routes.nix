{
  lib,
  self ? {
    outPath = ./.;
  },
  ...
}:

let
  graphContext = import ./graph/context.nix { inherit lib self; };
  helpers = import ./static-helpers.nix { inherit lib self; };
  directWanDefaults = import ./direct-wan-defaults.nix { inherit lib self; };
  laneDefaults = import ./lane-defaults.nix { inherit lib self; };
  overlayCoreSelection = import ./overlay-core-selection.nix { inherit lib self; };
  pathAvoidance = import ./graph/path-avoidance.nix { inherit lib; };
in
{
  apply =
    {
      topo,
      nodeName,
      node,
      routeContext,
      routeFacts ? routeContext.buildFacts topo,
      routeGraph ? graphContext.build (topo.links or { }) { },
      nonOverlayTransitGraph ? null,
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
            (
              (if family == 4 then routeContext.mkRoute4 else routeContext.mkRoute6) {
                dst = if family == 4 then helpers.default4 else helpers.default6For (topo.nodes or { });
                ${if family == 4 then "via4" else "via6"} = nextHop;
                proto = "default";
                intentKind = "default-reachability";
              }
              // lib.optionalAttrs (family == 4) {
                # The IPv4 default is advertised to clients as part of the
                # RFC 3442 classless routes so option 121 does not suppress the
                # default (RFC 3442 overrides option 3 when present).
                advertisedToClients = true;
              }
            )
          ];

      overlayTerminatingCores = overlayCoreSelection.overlayTerminatingCores topo;

      avoidsOverlayTransit =
        path:
        let
          len = builtins.length path;
          intermediate = if len <= 2 then [ ] else lib.sublist 1 (len - 2) path;
        in
        lib.all (node: !(builtins.elem node overlayTerminatingCores)) intermediate;

      shortestPathAvoiding =
        args:
        if nonOverlayTransitGraph == null then
          pathAvoidance.shortestPath routeGraph args
        else if args.src == args.dst then
          [ args.src ]
        else if builtins.elem args.src args.forbidden then
          null
        else
          nonOverlayTransitGraph.shortestPath {
            inherit (args) src dst;
          };

      nearestUplinkCore =
        let
          uplinks = routeFacts.uplinkCores or [ ];
          candidates = overlayCoreSelection.nonOverlayUplinkCores topo uplinks;
          reachable =
            lib.filter
              (
                candidate:
                candidate.path != null && builtins.length candidate.path >= 2 && avoidsOverlayTransit candidate.path
              )
              (
                map (target: {
                  inherit target;
                  path = shortestPathAvoiding {
                    src = nodeName;
                    dst = target;
                    forbidden = overlayTerminatingCores;
                  };
                }) candidates
              );
          sortedReachable = lib.sort (
            left: right:
            let
              leftLength = builtins.length left.path;
              rightLength = builtins.length right.path;
            in
            leftLength < rightLength || (leftLength == rightLength && left.target < right.target)
          ) reachable;
        in
        if uplinks == [ ] || lib.elem nodeName uplinks || sortedReachable == [ ] then
          null
        else
          (builtins.head sortedReachable).target;

      overlayUnderlayAccessNode =
        let
          accessNodes = overlayCoreSelection.underlayAccessNodesForCore topo nodeName;
          reachable = lib.filter (
            target:
            let
              path = routeGraph.shortestPath {
                src = nodeName;
                dst = target;
              };
            in
            path != null && builtins.length path >= 2
          ) accessNodes;
        in
        if reachable == [ ] then null else builtins.head (lib.sort (a: b: a < b) reachable);

      nearestDefaultTarget =
        if overlayUnderlayAccessNode != null then overlayUnderlayAccessNode else nearestUplinkCore;

      overlayUplinkNameSet = routeFacts.overlayUplinkNameSet or { };
      nonOverlayUplinkNames = routeFacts.nonOverlayUplinkNames or [ ];
      defaultReachabilityUplinkNames =
        routeFacts.defaultReachabilityUplinkNames or (topo.uplinkNames or [ ]);

      nearestUplinkCoreDefaultPlan =
        if nearestDefaultTarget == null then
          { }
        else
          let
            path = routeGraph.shortestPath {
              src = nodeName;
              dst = nearestDefaultTarget;
            };
            nonOverlayPath = shortestPathAvoiding {
              src = nodeName;
              dst = nearestDefaultTarget;
              forbidden = overlayTerminatingCores;
            };
            selectedPath =
              if overlayUnderlayAccessNode != null then
                path
              else if nonOverlayPath != null then
                nonOverlayPath
              else
                path;
            nextHop = nextHopWithPreferredUplinks {
              inherit topo;
              from = nodeName;
              to = builtins.elemAt selectedPath 1;
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
          if selectedPath == null || nextHop.linkName == null || skipOverlayGenericDefault then
            { }
          else
            {
              "${nextHop.linkName}" = {
                routes4 = nearestDefaultRoute 4 nextHop.via4;
                routes6 = nearestDefaultRoute 6 nextHop.via6;
              };
            };

      addDefaultTowardNearestUplinkCore = helpers.addRoutePlan node nearestUplinkCoreDefaultPlan;
    in
    {
      inherit addDefaultTowardNearestUplinkCore nearestUplinkCoreDefaultPlan;
      downstreamSelectorPolicyDefaultPlan = laneDefaults.downstreamSelectorPolicyDefaultPlan passArgs;
      policyDownstreamDefaultPlan = laneDefaults.policyDownstreamDefaultPlan passArgs;
      policyUpstreamSelectorDefaultPlan = laneDefaults.policyUpstreamSelectorDefaultPlan passArgs;
      upstreamSelectorPolicyLaneCoreDefaultPlan = laneDefaults.policyLaneCoreDefaultPlan passArgs;
      addDownstreamSelectorPolicyLaneDefaults = laneDefaults.addDownstreamSelectorPolicyDefaults passArgs;
      addPolicyDownstreamDefaults = laneDefaults.addPolicyDownstreamDefaults passArgs;
      addPolicyUpstreamSelectorLaneDefaults = laneDefaults.addPolicyUpstreamSelectorDefaults passArgs;
      addUpstreamSelectorPolicyLaneCoreDefaults = laneDefaults.addUpstreamSelectorPolicyLaneCoreDefaults passArgs;
      addDirectWanDefaults = directWanDefaults.apply { inherit node routeContext; };
    };
}
