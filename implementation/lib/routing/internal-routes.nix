{ lib, self ? { outPath = ./.; }, ... }:

let
  graphContext = import (self.outPath + "/implementation/lib/routing/graph/context.nix") { inherit lib self; };
  helpers = import (self.outPath + "/implementation/lib/routing/static-helpers.nix") { inherit lib self; };
  trace = import (self.outPath + "/lib/trace.nix") { };
  remotePrefixes = import (self.outPath + "/implementation/lib/routing/internal-routes/remote-prefixes.nix") {
    inherit lib self;
  };
  sitePlan = import (self.outPath + "/implementation/lib/routing/internal-routes/site-plan.nix") {
    inherit lib self;
  };
in
{
  buildRemotePrefixFacts = remotePrefixes.buildFacts;
  buildSitePlan = sitePlan.build;

  apply =
    { topo
    , nodeName
    , node
    , routeContext
    , routeFacts ? routeContext.buildFacts topo
    , remotePrefixFacts ? remotePrefixes.buildFacts topo
    , routeGraph ? graphContext.build (topo.links or { }) { }
    , realRouteGraph ? graphContext.build (topo.links or { }) {
        nodeNames = builtins.attrNames (topo.nodes or { });
      }
    , internalRoutePlan ? sitePlan.build {
        inherit
          topo
          routeContext
          routeFacts
          remotePrefixFacts
          routeGraph
          realRouteGraph
          ;
      }
    ,
    }:
    let
      perLink = internalRoutePlan.byNode.${nodeName} or { };
    in
    helpers.addRoutePlan node perLink;
}
