{ }:

let
  groupValues = keyFn: xs: builtins.groupBy keyFn xs;
  diagnosticsBuilder = import ./diagnostics.nix { };

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

      diagnostics = diagnosticsBuilder.build {
        inherit nodeNames remoteGroups remotePrefixFacts routeRows;
      };
    in
    {
      inherit byNode diagnostics;
    };
}
