{ }:

let
  sum = xs: builtins.foldl' (acc: x: acc + x) 0 xs;

  groupValues = keyFn: xs: builtins.groupBy keyFn xs;

  countRemoteByKind =
    remoteByNode: kind:
    sum (map (nodeFacts: builtins.length (nodeFacts.${kind} or [ ])) (builtins.attrValues remoteByNode));

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
        materializedRouteRows =
          builtins.foldl'
            (acc: row: acc + builtins.length (row.routes4 or [ ]) + builtins.length (row.routes6 or [ ]))
            0
            routeRows;
        nodes = builtins.length nodeNames;
      };
    in
    {
      inherit byNode diagnostics;
    };
}
