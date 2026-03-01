{ lib }:

{
  compute =
    { lib, site, enterprise, siteId, ordering, accessUnits, allUnits }:

    let
      validate = import ./roles/validate.nix { inherit lib; };
      derive = import ../../util/derive.nix { inherit lib; };

      orderingEdges =
        map (p: { a = builtins.elemAt p 0; b = builtins.elemAt p 1; })
          (lib.filter (p: builtins.isList p && builtins.length p == 2) ordering);

      uniq = xs: lib.unique xs;

      nodesInOrdering = uniq (lib.concatMap (e: [ e.a e.b ]) orderingEdges);

      countIn = n: xs: builtins.length (lib.filter (x: x == n) xs);

      indeg = n: countIn n (map (e: e.b) orderingEdges);
      outdeg = n: countIn n (map (e: e.a) orderingEdges);

      outsOf = n: lib.filter (e: e.a == n) orderingEdges;

      roleFromInputExplicit =
        unit:
        let
          n = toString unit;
        in
        if site ? units && site.units ? "${n}" then (site.units.${n}.role or null) else null;

      allowFanoutHere =
        n:
        let
          outs = outsOf n;
          targets = map (e: e.b) outs;
          allTargetsAreSinks = lib.all (t: outdeg t == 0) targets;
          # Allow policy-like fanout patterns even if role isn't explicitly provided:
          # - multiple outgoing edges
          # - all targets are sinks (access units)
          # - node is not a root (has a predecessor)
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
          go = seen: cur:
            if cur == null then
              seen
            else if lib.elem cur seen then
              throw "network-solver: transit.ordering contains a cycle at '${cur}'"
            else
              go (seen ++ [ cur ]) (nextOf cur);
        in
        if start == null then [ ] else go [ ] start;

      anyBranchInChain = lib.any (n: (outdeg n) > 1) chain;

      inferredRolesFromOrdering =
        let
          len = builtins.length chain;
          at = i: builtins.elemAt chain i;

          base =
            if len == 4 then {
              "${at 0}" = "core";
              "${at 1}" = "upstream-selector";
              "${at 2}" = "policy";
              "${at 3}" = "access";
            } else if len == 3 && anyBranchInChain then {
              # e.g. core -> upstream-selector -> policy, and policy fans out to access sinks
              "${at 0}" = "core";
              "${at 1}" = "upstream-selector";
              "${at 2}" = "policy";
            } else if len == 3 then {
              "${at 0}" = "core";
              "${at 1}" = "policy";
              "${at 2}" = "access";
            } else if len == 2 then {
              "${at 0}" = "core";
              "${at 1}" = "access";
            } else
              { };
        in
        builtins.foldl'
          (acc: u: acc // { "${toString u}" = "access"; })
          base
          accessUnits;

      roleFromInput =
        unit:
        let
          n = toString unit;
          explicit = roleFromInputExplicit n;
          inferred =
            if inferredRolesFromOrdering ? "${n}" then inferredRolesFromOrdering.${n} else null;
          derived = derive.roleForUnit n;
        in
        if explicit != null then explicit
        else if inferred != null then inferred
        else derived;

      missingRoles = lib.filter (u: roleFromInput u == null) allUnits;

      assertions =
        if missingRoles == [ ] then true else
        throw ''
          network-solver: missing required unit role(s)

          site: ${enterprise}.${siteId}
          units missing roles: ${lib.concatStringsSep ", " (map toString missingRoles)}
        '';

      policyUnit =
        let
          policies = lib.filter (u: (roleFromInput u) == "policy") allUnits;
        in
        if policies == [ ] then null else lib.head (lib.sort (a: b: toString a < toString b) policies);

      traversal = {
        mode = "ordering-chain";
        chain = chain;
        edges = orderingEdges;
        inferred = inferredRolesFromOrdering;
        coreUnitHint = coreByOrdering;
        policyFanout =
          if policyUnit == null then
            [ ]
          else
            map (e: e.b) (outsOf (toString policyUnit));
      };

    in
    {
      validate = validate;
      inherit roleFromInput chain orderingEdges traversal policyUnit assertions;
    };
}
