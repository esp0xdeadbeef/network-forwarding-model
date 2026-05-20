{ lib, ... }:

{
  collect =
    { site
    , topologyPairs
    , rolesResult
    ,
    }:
    let
      orderingUnits = lib.unique (
        lib.concatMap
          (
            p: if builtins.isList p && builtins.length p == 2 then map toString p else [ ]
          )
          topologyPairs
      );

      topologyNodeNames =
        if site ? topology && builtins.isAttrs site.topology && site.topology ? nodes && builtins.isAttrs site.topology.nodes then
          builtins.attrNames site.topology.nodes
        else
          [ ];

      forwardingSemanticsNodeNames =
        if
          site ? forwardingSemantics
          && builtins.isAttrs site.forwardingSemantics
          && site.forwardingSemantics ? nodes
          && builtins.isAttrs site.forwardingSemantics.nodes
        then
          builtins.attrNames site.forwardingSemantics.nodes
        else
          [ ];
    in
    lib.sort (a: b: a < b) (
      lib.unique (
        (if site ? units && builtins.isAttrs site.units then builtins.attrNames site.units else [ ])
        ++ (if site ? nodes && builtins.isAttrs site.nodes then builtins.attrNames site.nodes else [ ])
        ++ topologyNodeNames
        ++ forwardingSemanticsNodeNames
        ++ orderingUnits
        ++ (rolesResult.traversal.chain or [ ])
        ++ builtins.attrNames (rolesResult.traversal.inferred or { })
      )
    );
}
