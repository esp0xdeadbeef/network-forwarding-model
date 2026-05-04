{ lib }:

let
  accessUplinks = import ./lane-access-uplinks.nix { inherit lib; };
  coreUplinks = import ./lane-core-uplinks.nix { inherit lib; };
  overlayNameSetFor = import ./overlay-name-set.nix { inherit lib; };
in

{
  derive =
    {
      site,
      unitNames,
      topologyPairs,
      rolesResult,
      wanResult,
    }:
    let
      firstUnitByRole =
        role:
        let
          names = lib.sort (a: b: a < b) unitNames;
          hits = lib.filter (n: rolesResult.roleFromInput (toString n) == role) names;
        in
        if hits == [ ] then null else toString (builtins.head hits);

      downstreamSelectorUnit = firstUnitByRole "downstream-selector";
      upstreamSelectorUnit = firstUnitByRole "upstream-selector";
      policyUnit = if rolesResult.policyUnit == null then null else toString rolesResult.policyUnit;
      accessUnitNames =
        let
          names = lib.sort (a: b: a < b) unitNames;
        in
        map toString (lib.filter (n: rolesResult.roleFromInput (toString n) == "access") names);

      canonicalP2pLinkNameForEndpoints =
        endpointA: endpointB:
        let
          endpointAName = toString endpointA;
          endpointBName = toString endpointB;
          firstEndpoint = if endpointAName < endpointBName then endpointAName else endpointBName;
          secondEndpoint = if endpointAName < endpointBName then endpointBName else endpointAName;
        in
        "p2p-${firstEndpoint}-${secondEndpoint}";

      canonicalP2pLinkNameForEndpointsWithSuffix =
        endpointA: endpointB: suffix:
        "${canonicalP2pLinkNameForEndpoints endpointA endpointB}--${toString suffix}";

      baseP2pPairs = lib.filter (p: builtins.isList p && builtins.length p == 2) topologyPairs;

      allowedUplinksByAccessUnit = accessUplinks.derive { inherit site accessUnitNames; };
      overlayNameSet = overlayNameSetFor site;
      coreLaneResult = coreUplinks.derive {
        inherit
          canonicalP2pLinkNameForEndpoints
          site
          upstreamSelectorUnit
          wanResult
          ;
      };
      inherit (coreLaneResult)
        annotateCoreUplinkLane
        annotateMergedLinkLane
        linkSpecConnectsEndpoints
        ;

      basePairsWithoutSelectorBuses =
        if policyUnit == null then
          map annotateCoreUplinkLane baseP2pPairs
        else
          map annotateCoreUplinkLane (
            lib.filter (
              pair:
              let
                connectsDownstreamSelectorToPolicy =
                  downstreamSelectorUnit != null
                  && linkSpecConnectsEndpoints policyUnit downstreamSelectorUnit pair;
                connectsPolicyToUpstreamSelector =
                  upstreamSelectorUnit != null
                  && linkSpecConnectsEndpoints policyUnit upstreamSelectorUnit pair;
              in
              !(connectsDownstreamSelectorToPolicy || connectsPolicyToUpstreamSelector)
            ) baseP2pPairs
          );

      derivedLaneSpecs =
        if policyUnit == null then
          [ ]
        else
          (lib.concatMap (
            accessUnit:
            if downstreamSelectorUnit == null then
              [ ]
            else
              [
                {
                  a = policyUnit;
                  b = downstreamSelectorUnit;
                  lane = "access::${toString accessUnit}";
                  name =
                    canonicalP2pLinkNameForEndpointsWithSuffix policyUnit downstreamSelectorUnit
                      "access-${toString accessUnit}";
                }
              ]
          ) accessUnitNames)
          ++ (lib.concatMap (
            accessUnit:
            let
              uplinks = allowedUplinksByAccessUnit.${toString accessUnit} or [ ];
            in
            if upstreamSelectorUnit == null then
              [ ]
            else
              map (uplinkName: {
                a = policyUnit;
                b = upstreamSelectorUnit;
                lane = "access::${toString accessUnit}::uplink::${toString uplinkName}";
                name =
                  canonicalP2pLinkNameForEndpointsWithSuffix policyUnit upstreamSelectorUnit
                    "access-${toString accessUnit}--uplink-${toString uplinkName}";
              }
              // lib.optionalAttrs (builtins.hasAttr (toString uplinkName) overlayNameSet) {
                overlay = toString uplinkName;
              }) uplinks
          ) accessUnitNames);
    in
    {
      inherit
        accessUnitNames
        annotateMergedLinkLane
        downstreamSelectorUnit
        policyUnit
        upstreamSelectorUnit
        ;
      p2pLinkSpecs = basePairsWithoutSelectorBuses ++ derivedLaneSpecs;
    };
}
