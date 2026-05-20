{ lib, self ? { outPath = ./.; }, ... }:

let
  accessUplinks = import ./lane-access-uplinks.nix { inherit lib self; };
  coreUplinks = import ./lane-core-uplinks.nix { inherit lib self; };
  overlayNameSetFor = import ./overlay-name-set.nix { inherit lib self; };
  accessEdge = import ./lane-links/access-edge.nix { inherit lib; };
  names = import ./lane-links/names.nix { inherit lib; };
  selectorLanes = import ./lane-links/selector-lanes.nix { inherit lib; };
in

{
  derive =
    { site
    , unitNames
    , topologyPairs
    , rolesResult
    , wanResult
    , compilerIndexes
    ,
    }:
    let
      downstreamSelectorUnit = names.firstUnitByRole { inherit unitNames rolesResult; role = "downstream-selector"; };
      upstreamSelectorUnit = names.firstUnitByRole { inherit unitNames rolesResult; role = "upstream-selector"; };
      policyUnit = if rolesResult.policyUnit == null then null else toString rolesResult.policyUnit;
      accessUnitNames = names.unitsByRole { inherit unitNames rolesResult; role = "access"; };

      inherit (names)
        canonicalP2pLinkNameForEndpoints
        canonicalP2pLinkNameForEndpointsWithSuffix
        ;

      baseP2pPairs = lib.filter (p: builtins.isList p && builtins.length p == 2) topologyPairs;
      allowedUplinksByAccessUnit = accessUplinks.derive { inherit site accessUnitNames compilerIndexes; };
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

      annotateAccessEdgeLane = accessEdge.annotate {
        inherit
          accessUnitNames
          canonicalP2pLinkNameForEndpoints
          downstreamSelectorUnit
          linkSpecConnectsEndpoints
          ;
      };

      isSelectorBus =
        pair:
        policyUnit != null
        && (
          (
            downstreamSelectorUnit != null
            && linkSpecConnectsEndpoints policyUnit downstreamSelectorUnit pair
          )
          || (
            upstreamSelectorUnit != null
            && linkSpecConnectsEndpoints policyUnit upstreamSelectorUnit pair
          )
        );

      basePairs =
        map (pair: annotateAccessEdgeLane (annotateCoreUplinkLane pair)) (
          lib.filter (pair: !(isSelectorBus pair)) baseP2pPairs
        );

      derivedLaneSpecs = selectorLanes.derive {
        inherit
          accessUnitNames
          allowedUplinksByAccessUnit
          canonicalP2pLinkNameForEndpointsWithSuffix
          downstreamSelectorUnit
          overlayNameSet
          policyUnit
          upstreamSelectorUnit
          ;
      };
    in
    {
      inherit
        accessUnitNames
        annotateMergedLinkLane
        downstreamSelectorUnit
        policyUnit
        upstreamSelectorUnit
        ;
      p2pLinkSpecs = basePairs ++ derivedLaneSpecs;
    };
}
