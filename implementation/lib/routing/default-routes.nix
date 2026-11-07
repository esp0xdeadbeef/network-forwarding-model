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
  defaultRoutePolicy = import ./default-route-policy.nix { inherit lib self; };
  directWanDefaults = import ./direct-wan-defaults.nix { inherit lib self; };
  laneDefaults = import ./lane-defaults.nix { inherit lib self; };
  nearestTargetModule = import ./nearest-default-target.nix { inherit lib self; };
  overlayCoreSelection = import ./overlay-core-selection.nix { inherit lib self; };
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
        family: nextHop: lane:
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
              // lib.optionalAttrs (lane != null) { inherit lane; }
              // lib.optionalAttrs (family == 4) {
                # The IPv4 default is advertised to clients as part of the
                # RFC 3442 classless routes so option 121 does not suppress the
                # default (RFC 3442 overrides option 3 when present).
                advertisedToClients = true;
              }
            )
          ];

      overlayTerminatingCores = overlayCoreSelection.overlayTerminatingCores topo;

      resolved = nearestTargetModule.resolve {
        inherit
          topo
          nodeName
          routeGraph
          nonOverlayTransitGraph
          routeFacts
          overlayCoreSelection
          ;
      };
      inherit (resolved)
        overlayUnderlayAccessNode
        nearestDefaultTarget
        shortestPathAvoiding
        ;

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

            # A generic default is only installable on a lane whose modeled uplink
            # actually offers a default in that address family.
            #
            # The previous guard here was `nonOverlayUplinkNames != [ ] &&
            # selectedIsOverlayUplink`, i.e. "skip the overlay lane when the site
            # also has a non-overlay uplink". That inverted the question and failed
            # open: it depended on `topo.uplinkNames` still being populated at this
            # stage, and it treated "is an overlay lane" as the reason to withhold a
            # default. Both are wrong. The question is not what kind of link the
            # lane is, it is whether the lane's modeled uplink offers a default at
            # all (FS-315: the set of next hops a scope can forward its generic
            # reachability to must equal the set the model admits; an overlay that
            # carries peer prefixes offers no default).
            #
            # Measured failure this caused: `core-vpn-garnet-cobalt` is an
            # overlay-terminating core and not an uplink anchor, so its lane names
            # the `garnet` uplink and `garnet` offers no default in either family.
            # The guard evaluated false, a 0.0.0.0/0 was installed toward the
            # upstream selector, and the selector offers no default back on that
            # adjacency -- the router's own egress still worked while every client
            # behind it was blackholed.
            laneOffersDefault =
              family: uplinkName:
              uplinkName == null
              || builtins.hasAttr uplinkName (
                if family == 4 then routeFacts.uplinkHasDefault4Set or { } else routeFacts.uplinkHasDefault6Set or { }
              );
            accessLane =
              if (node.role or null) == "access" then
                let
                  accessUplinks = defaultRoutePolicy.anyTrafficDefaultUplinksForAccess topo nodeName;
                in
                {
                  access = nodeName;
                  uplink =
                    if accessUplinks == [ ] then null else builtins.head (lib.sort (a: b: a < b) accessUplinks);
                }
              else
                null;
          in
          if selectedPath == null || nextHop.linkName == null then
            { }
          else
            let
              routes4 =
                if laneOffersDefault 4 selectedUplinkName then
                  nearestDefaultRoute 4 nextHop.via4 accessLane
                else
                  [ ];
              routes6 =
                if laneOffersDefault 6 selectedUplinkName then
                  nearestDefaultRoute 6 nextHop.via6 accessLane
                else
                  [ ];
            in
            # Withhold the plan entirely when neither family is installable, so a
            # node whose only adjacency offers no default ends up with no generic
            # default rather than an empty-route plan that still marks the lane.
            if routes4 == [ ] && routes6 == [ ] then
              { }
            else
              {
                "${nextHop.linkName}" = {
                  inherit routes4 routes6;
                };
              };

      addDefaultTowardNearestUplinkCore = helpers.addRoutePlan node nearestUplinkCoreDefaultPlan;
    in
    {
      inherit addDefaultTowardNearestUplinkCore nearestUplinkCoreDefaultPlan;
      downstreamSelectorPolicyDefaultPlan = laneDefaults.downstreamSelectorPolicyDefaultPlan passArgs;
      policyUpstreamSelectorDefaultPlan = laneDefaults.policyUpstreamSelectorDefaultPlan passArgs;
      upstreamSelectorPolicyLaneCoreDefaultPlan = laneDefaults.policyLaneCoreDefaultPlan passArgs;
      addDownstreamSelectorPolicyLaneDefaults = laneDefaults.addDownstreamSelectorPolicyDefaults passArgs;
      addPolicyUpstreamSelectorLaneDefaults = laneDefaults.addPolicyUpstreamSelectorDefaults passArgs;
      addPolicyUpstreamSelectorCombinedDefaults = laneDefaults.addPolicyUpstreamSelectorCombinedDefaults passArgs;
      addUpstreamSelectorPolicyLaneCoreDefaults = laneDefaults.addUpstreamSelectorPolicyLaneCoreDefaults passArgs;
      addUpstreamSelectorPolicyCombinedCoreDefaults = laneDefaults.addUpstreamSelectorPolicyCombinedCoreDefaults passArgs;
      addDirectWanDefaults = directWanDefaults.apply { inherit node routeContext; };
    };
}
