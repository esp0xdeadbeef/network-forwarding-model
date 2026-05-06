{ lib, self ? { outPath = ./.; }, ... }:

let
  accessUplinks = import ./lane-access-uplinks.nix { inherit lib self; };
  coreUplinks = import ./lane-core-uplinks.nix { inherit lib self; };
  overlayNameSetFor = import ./overlay-name-set.nix { inherit lib self; };
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

      annotateAccessEdgeLane =
        pair:
        let
          matchingAccessUnits =
            lib.filter (
              accessUnit:
              downstreamSelectorUnit != null && linkSpecConnectsEndpoints accessUnit downstreamSelectorUnit pair
            ) accessUnitNames;
        in
        if builtins.length matchingAccessUnits == 1 then
          {
            a = if builtins.isList pair then toString (builtins.elemAt pair 0) else toString pair.a;
            b = if builtins.isList pair then toString (builtins.elemAt pair 1) else toString pair.b;
            name =
              if builtins.isAttrs pair && (pair.name or null) != null then
                pair.name
              else
                canonicalP2pLinkNameForEndpoints
                  (if builtins.isList pair then builtins.elemAt pair 0 else pair.a)
                  (if builtins.isList pair then builtins.elemAt pair 1 else pair.b);
          }
          // lib.optionalAttrs (builtins.isAttrs pair && (pair.lane or null) != null) { lane = pair.lane; }
          // lib.optionalAttrs (builtins.isAttrs pair && (pair.overlay or null) != null) { overlay = pair.overlay; }
          // lib.optionalAttrs (builtins.isAttrs pair && (pair.uplinks or null) != null) { uplinks = pair.uplinks; }
          // {
            laneMeta = {
              kind = "access-edge";
              access = builtins.head matchingAccessUnits;
              uplink = null;
              uplinks = [ ];
            };
          }
        else
          pair;

      basePairsWithoutSelectorBuses =
        if policyUnit == null then
          map (pair: annotateAccessEdgeLane (annotateCoreUplinkLane pair)) baseP2pPairs
        else
          map (pair: annotateAccessEdgeLane (annotateCoreUplinkLane pair)) (
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
                  laneMeta = {
                    kind = "access";
                    access = toString accessUnit;
                    uplink = null;
                    uplinks = [ ];
                  };
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
                laneMeta = {
                  kind = "access-uplink";
                  access = toString accessUnit;
                  uplink = toString uplinkName;
                  uplinks = [ (toString uplinkName) ];
                };
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
