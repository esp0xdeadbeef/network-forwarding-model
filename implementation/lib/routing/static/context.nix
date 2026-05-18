{ lib, self ? { outPath = ./.; }, ... }:

let
  routeContext = import (self.outPath + "/implementation/lib/routing/route-context.nix") { inherit lib self; };
  graphContext = import (self.outPath + "/implementation/lib/routing/graph/context.nix") { inherit lib self; };
  internalRoutes = import (self.outPath + "/implementation/lib/routing/internal-routes.nix") { inherit lib self; };
in
{
  build =
    topo:
    {
      inherit topo routeContext;
      routeGraph = graphContext.build (topo.links or { });
      routeFacts = routeContext.buildFacts topo;
      remotePrefixFacts = internalRoutes.buildRemotePrefixFacts topo;
      skipInternal = builtins.getEnv "S88_NFM_PROFILE_SKIP_INTERNAL_ROUTES" == "1";
      skipNearest = builtins.getEnv "S88_NFM_PROFILE_SKIP_NEAREST_DEFAULTS" == "1";
      skipLaneDefaults = builtins.getEnv "S88_NFM_PROFILE_SKIP_LANE_DEFAULTS" == "1";
      skipExternalIngress = builtins.getEnv "S88_NFM_PROFILE_SKIP_EXTERNAL_INGRESS_DEFAULTS" == "1";
      skipDirectWan = builtins.getEnv "S88_NFM_PROFILE_SKIP_DIRECT_WAN_DEFAULTS" == "1";
      skipUplinkLearned = builtins.getEnv "S88_NFM_PROFILE_SKIP_UPLINK_LEARNED" == "1";
    };
}
