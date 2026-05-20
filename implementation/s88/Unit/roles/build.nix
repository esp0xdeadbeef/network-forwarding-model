{ lib, self ? { outPath = ./.; }, ... }:

{
  compute =
    { lib
    , site
    , enterprise
    , siteId
    , ordering
    , accessUnits
    , allUnits
    ,
    }:

    let
      validate = import ./validate.nix { inherit lib self; };
      inputRoleMod = import ./input-role.nix { inherit lib self; };
      orderingGraph = import ./ordering-graph.nix { inherit lib self; };
      forwardingMarkersMod = import ./forwarding-markers.nix { inherit lib self; };

      graph = orderingGraph ordering;
      orderingEdges = graph.edges;
      chain = graph.chain;
      coreByOrdering = graph.root;

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
        policyFanout = if policyUnit == null then [ ] else map (e: e.b) (graph.outsOf (toString policyUnit));
      };

      forwardingMarkers = forwardingMarkersMod.build { inherit allUnits graph roleFromInput; };

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
