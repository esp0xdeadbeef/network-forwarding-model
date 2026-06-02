{ lib, self ? { outPath = ./.; }, ... }:

let
  routeContext = import (self.outPath + "/implementation/lib/routing/route-context.nix") { inherit lib self; };
  graphContext = import (self.outPath + "/implementation/lib/routing/graph/context.nix") { inherit lib self; };
  internalRoutes = import (self.outPath + "/implementation/lib/routing/internal-routes.nix") { inherit lib self; };
  link = import (self.outPath + "/implementation/lib/topology/link-utils.nix") { inherit lib self; };
  overlayCoreSelection = import (self.outPath + "/implementation/lib/routing/overlay-core-selection.nix") {
    inherit lib self;
  };
in
rec {
  buildWith =
    { topo
    , routeGraph ? graphContext.build (topo.links or { }) {
        nodeNames = builtins.attrNames (topo.nodes or { });
      }
    ,
    }:
    let
      routeFacts = routeContext.buildFacts topo;
      remotePrefixFacts = internalRoutes.buildRemotePrefixFacts topo;
      overlayTerminatingCores = overlayCoreSelection.overlayTerminatingCores topo;
      overlayTerminatingCoreSet = builtins.listToAttrs (
        map (name: {
          name = toString name;
          value = true;
        }) overlayTerminatingCores
      );
      nonOverlayTransitLinks = builtins.filter
        (
          linkName:
          let
            members = link.membersOf ((topo.links or { }).${linkName});
          in
          !builtins.any (member: overlayTerminatingCoreSet.${toString member} or false) members
        )
        (builtins.attrNames (topo.links or { }));
      nonOverlayTransitLinkSet = builtins.listToAttrs (
        map (name: {
          inherit name;
          value = (topo.links or { }).${name};
        }) nonOverlayTransitLinks
      );
      realRouteGraph = graphContext.build (topo.links or { }) {
        nodeNames = builtins.attrNames (topo.nodes or { });
      };
      nonOverlayTransitGraph = graphContext.build nonOverlayTransitLinkSet {
        nodeNames = builtins.attrNames (topo.nodes or { });
      };
      skipInternal = builtins.getEnv "S88_NFM_PROFILE_SKIP_INTERNAL_ROUTES" == "1";
      internalRoutePlan =
        if skipInternal then
          {
            byNode = { };
            diagnostics = {
              planner = "skipped";
              usesExistingPerNodeExpansion = false;
              nodes = 0;
            };
          }
        else
          internalRoutes.buildSitePlan {
            inherit
              topo
              routeContext
              routeFacts
              remotePrefixFacts
              routeGraph
              realRouteGraph
              ;
          };
    in
    {
      inherit topo routeContext;
      inherit routeGraph;
      inherit
        realRouteGraph
        nonOverlayTransitGraph
        routeFacts
        remotePrefixFacts
        internalRoutePlan
        ;
      inherit skipInternal;
      skipNearest = builtins.getEnv "S88_NFM_PROFILE_SKIP_NEAREST_DEFAULTS" == "1";
      skipLaneDefaults = builtins.getEnv "S88_NFM_PROFILE_SKIP_LANE_DEFAULTS" == "1";
      skipExternalIngress = builtins.getEnv "S88_NFM_PROFILE_SKIP_EXTERNAL_INGRESS_DEFAULTS" == "1";
      skipDirectWan = builtins.getEnv "S88_NFM_PROFILE_SKIP_DIRECT_WAN_DEFAULTS" == "1";
      skipUplinkLearned = builtins.getEnv "S88_NFM_PROFILE_SKIP_UPLINK_LEARNED" == "1";
    };

  build = topo: buildWith { inherit topo; };
}
