{ lib }:

{
  compute =
    {
      lib,
      site,
      enterprise,
      siteId,
      ordering,
      accessUnits,
      allUnits,
    }:

    let
      validate = import ./roles/validate.nix { inherit lib; };

      topologyNodes =
        if
          site ? topology
          && builtins.isAttrs site.topology
          && site.topology ? nodes
          && builtins.isAttrs site.topology.nodes
        then
          site.topology.nodes
        else
          { };

      orderingEdges = map (p: {
        a = builtins.elemAt p 0;
        b = builtins.elemAt p 1;
      }) (lib.filter (p: builtins.isList p && builtins.length p == 2) ordering);

      uniq = xs: lib.unique xs;

      nodesInOrdering = uniq (
        lib.concatMap (e: [
          e.a
          e.b
        ]) orderingEdges
      );

      countIn = n: xs: builtins.length (lib.filter (x: x == n) xs);

      indeg = n: countIn n (map (e: e.b) orderingEdges);
      outdeg = n: countIn n (map (e: e.a) orderingEdges);

      outsOf = n: lib.filter (e: e.a == n) orderingEdges;

      roleFromInputExplicit =
        node:
        let
          n = toString node;
        in
        if topologyNodes ? "${n}" then
          (topologyNodes.${n}.role or null)
        else if site ? nodes && site.nodes ? "${n}" then
          (site.nodes.${n}.role or null)
        else if site ? units && site.units ? "${n}" then
          (site.units.${n}.role or null)
        else
          null;

      allowFanoutHere =
        n:
        let
          outs = outsOf n;
          targets = map (e: e.b) outs;
          allTargetsAreSinks = lib.all (t: outdeg t == 0) targets;
          notRoot = (indeg n) > 0;
        in
        (builtins.length outs) > 1 && allTargetsAreSinks && notRoot;

      nextOf =
        n:
        let
          outs = outsOf n;
        in
        if outs == [ ] then
          null
        else if builtins.length outs == 1 then
          (builtins.elemAt outs 0).b
        else if allowFanoutHere n then
          null
        else
          throw "network-solver: transit.ordering must not branch from '${n}' (multiple outgoing edges)";

      coreByOrdering =
        let
          roots = lib.filter (n: indeg n == 0) nodesInOrdering;
        in
        if roots == [ ] then null else lib.head (lib.sort (a: b: a < b) roots);

      chain =
        let
          start = coreByOrdering;
          go =
            seen: cur:
            if cur == null then
              seen
            else if lib.elem cur seen then
              throw "network-solver: transit.ordering contains a cycle at '${cur}'"
            else
              go (seen ++ [ cur ]) (nextOf cur);
        in
        if start == null then [ ] else go [ ] start;

      roleFromInput = node: roleFromInputExplicit node;

      missingRoles = lib.filter (n: roleFromInput n == null || roleFromInput n == "") allUnits;

      assertions =
        if missingRoles == [ ] then
          true
        else
          throw ''
            network-solver: missing required node role(s)

            site: ${enterprise}.${siteId}
            nodes missing roles: ${lib.concatStringsSep ", " (map toString missingRoles)}
          '';

      policyUnits = lib.filter (n: (roleFromInput n) == "policy") allUnits;
      _exactlyOnePolicy =
        if builtins.length policyUnits == 1 then
          true
        else
          throw ''
            network-solver: expected exactly one node with role='policy'

            site: ${enterprise}.${siteId}
            found: ${toString (builtins.length policyUnits)}
            nodes: ${lib.concatStringsSep ", " (map toString policyUnits)}
          '';

      policyUnit = builtins.seq _exactlyOnePolicy (
        lib.head (lib.sort (a: b: toString a < toString b) policyUnits)
      );

      traversal = {
        mode = "ordering-chain";
        chain = chain;
        edges = orderingEdges;
        inferred = { };
        coreUnitHint = coreByOrdering;
        policyFanout = if policyUnit == null then [ ] else map (e: e.b) (outsOf (toString policyUnit));
      };

    in
    {
      validate = validate;
      inherit
        roleFromInput
        chain
        orderingEdges
        traversal
        policyUnit
        assertions
        ;
    };
}
