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
      inputRoleMod = import ./roles/input-role.nix { inherit lib; };

      orderingEdges = map (p: {
        a = builtins.elemAt p 0;
        b = builtins.elemAt p 1;
      }) (lib.filter (p: builtins.isList p && builtins.length p == 2) ordering);

      uniq = xs: lib.unique xs;

      sortedStrings = xs: lib.sort (a: b: a < b) (lib.unique (map toString xs));

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
      insOf = n: lib.filter (e: e.b == n) orderingEdges;

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
          throw "network-forwarding-model: transit.ordering must not branch from '${n}' (multiple outgoing edges)";

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
              throw "network-forwarding-model: transit.ordering contains a cycle at '${cur}'"
            else
              go (seen ++ [ cur ]) (nextOf cur);
        in
        if start == null then [ ] else go [ ] start;

      chainIndexOf =
        nodeName:
        let
          indexed = lib.imap0 (idx: value: { inherit idx value; }) chain;
          hits = lib.filter (x: x.value == nodeName) indexed;
        in
        if hits == [ ] then null else (builtins.head hits).idx;

      roleFromInput = inputRoleMod.roleFromSite site;

      missingRoles = lib.filter (n: roleFromInput n == null || roleFromInput n == "") allUnits;

      assertions =
        if missingRoles == [ ] then
          true
        else
          throw ''
            network-forwarding-model: missing required node role(s)

            site: ${enterprise}.${siteId}
            nodes missing roles: ${lib.concatStringsSep ", " (map toString missingRoles)}
          '';

      policyUnits = lib.filter (n: (roleFromInput n) == "policy") allUnits;
      _exactlyOnePolicy =
        if builtins.length policyUnits == 1 then
          true
        else
          throw ''
            network-forwarding-model: expected exactly one node with role='policy'

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

      forwardingMarkers = builtins.listToAttrs (
        map (
          unitName0:
          let
            unitName = toString unitName0;
            role = roleFromInput unitName;
            incoming = sortedStrings (map (e: e.a) (insOf unitName));
            outgoing = sortedStrings (map (e: e.b) (outsOf unitName));
            participates = lib.elem unitName nodesInOrdering;
            chainIndex = chainIndexOf unitName;

            accessTermination = role == "access";
            policyEnforcement = role == "policy";
            transitForwarding =
              participates
              || role == "core"
              || role == "policy"
              || role == "downstream-selector"
              || role == "upstream-selector";
            transitRoutingAuthority =
              role == "core" || role == "policy" || role == "downstream-selector" || role == "upstream-selector";
            upstreamSelectionAuthority = role == "upstream-selector";

            functions = lib.sort (a: b: a < b) (
              lib.unique (
                (lib.optional accessTermination "access-gateway")
                ++ (lib.optional policyEnforcement "policy-enforcement")
                ++ (lib.optional (role == "downstream-selector") "downstream-selection")
                ++ (lib.optional transitForwarding "transit-forwarder")
                ++ (lib.optional (role == "core") "routing-core")
                ++ (lib.optional upstreamSelectionAuthority "upstream-selection")
              )
            );
          in
          {
            name = unitName;
            value = {
              inherit role functions;
              traversal = {
                participates = participates;
                chainIndex = chainIndex;
                entry = participates && incoming == [ ];
                terminal = participates && outgoing == [ ];
                incoming = incoming;
                outgoing = outgoing;
              };
              responsibilities = {
                accessTermination = accessTermination;
                policyEnforcement = policyEnforcement;
                transitForwarding = transitForwarding;
              };
              authority = {
                attachedPrefixRouting = accessTermination;
                transitRouting = transitRoutingAuthority;
                upstreamSelection = upstreamSelectionAuthority;
              };
            };
          }
        ) allUnits
      );

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
        forwardingMarkers
        ;
    };
}
