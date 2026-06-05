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
  coordinator = import ./site-plan/coordinator.nix { };

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
        inherit mode nodeNames remotePrefixFacts;
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
      baseDiagnostics = materialized.diagnostics;
      completion = coordinator.build {
        siteId = topo.siteId or null;
        testedHypothesis = "H2 internal route expansion shared route group planner";
        submoduleRecords = [
          {
            id = "FS-940-HDS-010-SDS-020-SMS-020";
            name = "route-atom-index";
            claimsRouteAtomAuthority = true;
            recordCount = builtins.length (rows.entriesByKind or [ ]);
          }
          {
            id = "FS-940-HDS-010-SDS-020-SMS-030";
            name = "source-eligibility-matrix";
            claimsRouteAtomAuthority = false;
            recordCount = builtins.length (builtins.attrNames (rows.remoteGroups or { }));
          }
          {
            id = "FS-940-HDS-010-SDS-020-SMS-040";
            name = "next-hop-equivalence-table";
            claimsRouteAtomAuthority = false;
            recordCount = baseDiagnostics.nextHopIdentities or 0;
          }
          {
            id = "FS-940-HDS-010-SDS-020-SMS-050";
            name = "forwarding-equivalence-group-planner";
            claimsRouteAtomAuthority = false;
            recordCount = builtins.length routeRows;
          }
          {
            id = "FS-940-HDS-010-SDS-020-SMS-060";
            name = "route-exception-layer";
            claimsRouteAtomAuthority = false;
            recordCount = 0;
          }
          {
            id = "FS-940-HDS-010-SDS-020-SMS-070";
            name = "one-pass-route-materializer";
            claimsRouteAtomAuthority = false;
            recordCount = baseDiagnostics.materializedRouteRows or 0;
          }
          {
            id = "FS-940-HDS-010-SDS-020-SMS-080";
            name = "route-cardinality-equivalence-diagnostics";
            claimsRouteAtomAuthority = false;
            recordCount = (baseDiagnostics.routeAtoms.tenant or 0) + (baseDiagnostics.routeAtoms.overlay or 0) + (baseDiagnostics.routeAtoms.p2p or 0);
          }
        ];
      };
      diagnostics = (rows.diagnostics or { }) // baseDiagnostics // {
        coordinator = completion.diagnostics;
      };
    in
    trace.emit "routing:internal:site-plan:nodes=${toString diagnostics.nodes}:planner=${diagnostics.planner}:tenantAtoms=${toString diagnostics.routeAtoms.tenant}:overlayAtoms=${toString diagnostics.routeAtoms.overlay}:p2pAtoms=${toString diagnostics.routeAtoms.p2p}" {
      inherit diagnostics;
      completionRecords = completion.records;
      inherit (materialized) byNode;
    };
}
