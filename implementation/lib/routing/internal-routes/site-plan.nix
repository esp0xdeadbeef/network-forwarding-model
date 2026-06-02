{ lib, self ? { outPath = ./.; }, ... }:

let
  graphContext = import (self.outPath + "/implementation/lib/routing/graph/context.nix") { inherit lib self; };
  helpers = import (self.outPath + "/implementation/lib/routing/static-helpers.nix") { inherit lib self; };
  trace = import (self.outPath + "/lib/trace.nix") { };
  remotePrefixes = import (self.outPath + "/implementation/lib/routing/internal-routes/remote-prefixes.nix") {
    inherit lib self;
  };
  sourceRows = import ./site-plan/source-rows.nix { inherit lib; };
  groupResolver = import ./site-plan/resolve-groups.nix { inherit lib self; };
  materializer = import ./site-plan/materialize.nix { };

in
{
  build =
    { topo
    , routeContext
    , routeFacts ? routeContext.buildFacts topo
    , remotePrefixFacts ? remotePrefixes.buildFacts topo
    , routeGraph ? graphContext.build (topo.links or { }) { }
    , realRouteGraph ? graphContext.build (topo.links or { }) {
        nodeNames = builtins.attrNames (topo.nodes or { });
      }
    ,
    }:
    let
      inherit (routeContext)
        mkRoute4
        mkRoute6
        ;
      nodeNames = builtins.attrNames (topo.nodes or { });
      mode = helpers.aggregationMode topo;

      rows = sourceRows.build {
        inherit nodeNames remotePrefixFacts;
        nodes = topo.nodes or { };
        includeP2p = builtins.getEnv "S88_NFM_PROFILE_SKIP_INTERNAL_P2P" != "1";
        includeTenant = builtins.getEnv "S88_NFM_PROFILE_SKIP_INTERNAL_TENANT" != "1";
        includeOverlay = builtins.getEnv "S88_NFM_PROFILE_SKIP_INTERNAL_OVERLAY" != "1";
      };

      routeRows = groupResolver.build {
        inherit
          mode
          mkRoute4
          mkRoute6
          realRouteGraph
          remotePrefixFacts
          routeContext
          routeFacts
          routeGraph
          topo
          ;
        inherit (rows) remoteGroups;
      };

      materialized = materializer.build {
        inherit nodeNames remotePrefixFacts routeRows;
        inherit (rows) remoteGroups;
      };
      diagnostics = materialized.diagnostics;
    in
    trace.emit "routing:internal:site-plan:nodes=${toString diagnostics.nodes}:planner=${diagnostics.planner}:tenantAtoms=${toString diagnostics.routeAtoms.tenant}:overlayAtoms=${toString diagnostics.routeAtoms.overlay}:p2pAtoms=${toString diagnostics.routeAtoms.p2p}" {
      inherit diagnostics;
      inherit (materialized) byNode;
    };
}
