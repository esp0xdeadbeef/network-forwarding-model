{ lib, self ? { outPath = ./.; }, ... }:

{
  build =
    { lib
    , site
    , localPool
    , rolesResult ? null
    , roleFromInput ? (if rolesResult != null then rolesResult.roleFromInput else (_: null))
    , nodesBase ? (site.nodes or site.units or { })
    ,
    }:

    let
      uplinkSpecs = import ./core/uplink-specs.nix { inherit lib self; };
      invariants = import ./core/invariants.nix { inherit lib self; };
      wanLinks = import ./core/wan-links.nix { inherit lib self; };

      allUnits = builtins.attrNames nodesBase;

      coreUnits = lib.sort (a: b: toString a < toString b) (
        lib.filter (u: (roleFromInput u) == "core") allUnits
      );

      explicitInputs = uplinkSpecs.explicitInputs site;

      specsByUnit = lib.listToAttrs (
        map
          (
            unitName:
            {
              name = unitName;
              value = uplinkSpecs.mergeForUnit {
                inherit
                  explicitInputs
                  unitName
                  ;
                nodeInputs = uplinkSpecs.nodeInputs nodesBase unitName;
              };
            }
          )
          coreUnits
      );

      specsForUnit = unitName: specsByUnit.${unitName} or [ ];

      declaredUnits = lib.filter (unitName: builtins.length (specsForUnit unitName) > 0) coreUnits;

      declaredNames = lib.sort (a: b: a < b) (
        lib.unique (lib.concatMap (unitName: map (spec: spec.name) (specsForUnit unitName)) declaredUnits)
      );

      hasForwardingAddress = spec: (spec.addr4 or null) != null || (spec.addr6 or null) != null;

      forwardingSpecsForUnit = unitName: lib.filter hasForwardingAddress (specsForUnit unitName);

      forwardingUnits =
        lib.filter (unitName: builtins.length (forwardingSpecsForUnit unitName) > 0) coreUnits;

      nameEntries = lib.concatMap
        (
          unitName:
          map
            (uplinkSpec: {
              name = uplinkSpec.name;
              value = toString unitName;
            })
            (forwardingSpecsForUnit unitName)
        )
        forwardingUnits;

      forwardingSpecs = lib.concatMap
        (
          unitName:
          map
            (uplink: {
              unitName = toString unitName;
              inherit uplink;
            })
            (forwardingSpecsForUnit unitName)
        )
        forwardingUnits;

      _haveCore = invariants.requireCoreUnits coreUnits;

      _haveDeclaredUplinks = invariants.requireDeclaredUplinks declaredUnits;

      _uniqueNames = invariants.requireUniqueForwardingNames nameEntries;

      _completeEndpoints =
        builtins.seq _uniqueNames (invariants.requireCompleteEndpoints forwardingSpecs);

      uplinkCoreByName = lib.listToAttrs nameEntries;

      uplinkNames = lib.sort (a: b: a < b) (lib.unique (builtins.attrNames uplinkCoreByName));

    in
    builtins.seq _haveCore (
      builtins.seq _haveDeclaredUplinks (
        builtins.seq _completeEndpoints {
          coreUnits = coreUnits;
          uplinkCores = forwardingUnits;
          uplinkCoreByName = uplinkCoreByName;
          uplinkNames = uplinkNames;
          declaredUplinkCores = declaredUnits;
          declaredUplinkNames = declaredNames;
          wanLinks = wanLinks.build forwardingSpecs;
        }
      )
    );
}
