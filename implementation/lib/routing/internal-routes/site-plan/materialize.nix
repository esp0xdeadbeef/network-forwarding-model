{ }:

let
  sum = xs: builtins.foldl' (acc: x: acc + x) 0 xs;

  groupValues = keyFn: xs: builtins.groupBy keyFn xs;

  countRemoteByKind =
    remoteByNode: kind:
    sum (map (nodeFacts: builtins.length (nodeFacts.${kind} or [ ])) (builtins.attrValues remoteByNode));

  countRows =
    predicate: rows:
    builtins.length (builtins.filter predicate rows);

in
{
  build =
    { nodeNames
    , remoteGroups
    , remotePrefixFacts
    , routeRows
    ,
    }:
    let
      byNodeLink = groupValues (row: "${row.nodeName}\n${row.linkName}") routeRows;
      linksByNode = groupValues (row: row.nodeName) routeRows;

      buildNodePlan =
        nodeName:
        let
          nodeRows = linksByNode.${nodeName} or [ ];
          linkNames = builtins.attrNames (groupValues (row: row.linkName) nodeRows);
        in
        builtins.listToAttrs (
          map
            (
              linkName:
              let
                rows = byNodeLink."${nodeName}\n${linkName}" or [ ];
              in
              {
                name = linkName;
                value = {
                  plannedRoutesNormalized = true;
                  routes4 = builtins.concatLists (map (row: row.routes4 or [ ]) rows);
                  routes6 = builtins.concatLists (map (row: row.routes6 or [ ]) rows);
                };
              }
            )
            linkNames
        );

      byNode = builtins.listToAttrs (
        map
          (nodeName: {
            name = nodeName;
            value = buildNodePlan nodeName;
          })
          nodeNames
      );

      remoteByNode = remotePrefixFacts.remoteByNode or { };
      routeDiagnostics = map (row: row.diagnostics or { }) routeRows;
      p2pExactGroups = countRows (row: ((row.equivalenceKey or { }).exceptionClass or null) == "point-to-point-exact") routeRows;
      runtimeSourceFileGroups = countRows (row: ((row.equivalenceKey or { }).exceptionClass or null) == "runtime-source-file") routeRows;
      selectedScopeGroups =
        countRows
          (
            row:
            let
              key = row.equivalenceKey or { };
            in
            (key.overlay or null) != null || (key.uplink or null) != null || (key.access or null) != null
          )
          routeRows;
      countDiagnostic = field: sum (map (diag: diag.${field} or 0) routeDiagnostics);
      exactOnlyCount = countDiagnostic "exactOnlyCount";
      prefixSummaryCandidateCount = countDiagnostic "prefixSummaryCandidateCount";
      rejectedAggregationCount = countDiagnostic "rejectedAggregationCount";
      finalMaterializedRouteCount = countDiagnostic "finalMaterializedRouteCount";
      diagnostics = {
        planner = "scratch-site-wide";
        usesExistingPerNodeExpansion = false;
        routeAtoms = {
          tenant = builtins.length (remotePrefixFacts.tenantOwnerEntries or [ ]);
          overlay = builtins.length (remotePrefixFacts.overlayRouteEntries or [ ]);
          p2p = builtins.length (remotePrefixFacts.p2pEntries or [ ]);
        };
        sourceEligibilityPairs = {
          tenant = countRemoteByKind remoteByNode "tenant";
          overlay = countRemoteByKind remoteByNode "overlay";
          p2p = countRemoteByKind remoteByNode "p2p";
        };
        nextHopIdentities = builtins.length (builtins.attrNames remoteGroups);
        forwardingEquivalenceKeys = builtins.length routeRows;
        exactOnlyCount = exactOnlyCount;
        exactDeduplicationCount = countDiagnostic "exactDeduplicationCount";
        prefixSummaryCandidateCount = prefixSummaryCandidateCount;
        rejectedAggregationCount = rejectedAggregationCount;
        finalMaterializedRouteCount = finalMaterializedRouteCount;
        materializer = {
          sms = "FS-940-HDS-010-SDS-020-SMS-070";
          source = "finished-site-plan";
          perInterfaceNormalizationAuthoritative = false;
          routeRows = builtins.length routeRows;
          exactOnlyCount = exactOnlyCount;
          prefixSummaryCandidateCount = prefixSummaryCandidateCount;
          rejectedAggregationCount = rejectedAggregationCount;
          finalMaterializedRouteCount = finalMaterializedRouteCount;
        };
        nextHopEquivalence = {
          sms = "FS-940-HDS-010-SDS-020-SMS-040";
          resolvedOncePerDistinctTuple = true;
          keyFields = [
            "sourceNode"
            "destinationOwner"
            "routeKind"
            "overlay"
            "uplink"
            "access"
            "serviceName"
            "hopNode"
            "linkName"
            "via4"
            "via6"
            "routeIntentClass"
          ];
          entries = map (row: row.equivalenceKey or { }) routeRows;
        };
        forwardingEquivalencePlanner = {
          sms = "FS-940-HDS-010-SDS-020-SMS-050";
          source = "route-atom-index-and-next-hop-equivalence";
          routeRows = builtins.length routeRows;
          preservesSelectedScopes = selectedScopeGroups > 0;
          keyFields = [
            "family"
            "sourceNode"
            "linkName"
            "nextHop"
            "routeIntentClass"
            "overlay"
            "uplink"
            "access"
            "serviceName"
            "exceptionClass"
            "sourceFile"
          ];
        };
        routeExceptionLayer = {
          sms = "FS-940-HDS-010-SDS-020-SMS-060";
          source = "after-forwarding-equivalence-groups";
          mutatesCommonGroups = false;
          inherit p2pExactGroups runtimeSourceFileGroups selectedScopeGroups;
        };
        materializedRouteRows =
          builtins.foldl'
            (acc: row: acc + builtins.length (row.routes4 or [ ]) + builtins.length (row.routes6 or [ ]))
            0
            routeRows;
        nodes = builtins.length nodeNames;
        routeCardinalityEquivalence = {
          sms = "FS-940-HDS-010-SDS-020-SMS-080";
          routeAtomCount = builtins.length (
            builtins.concatLists (map (row: ((row.equivalenceKey or { }).routeAtomIds or [ ])) routeRows)
          );
          inherit exactOnlyCount prefixSummaryCandidateCount rejectedAggregationCount finalMaterializedRouteCount;
          hasEquivalenceKeys = builtins.length routeRows > 0;
          provesBeforePromotion = true;
        };
      };
    in
    {
      inherit byNode diagnostics;
    };
}
