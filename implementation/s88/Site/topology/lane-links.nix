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
      allowedUplinksByAccessUnit = (accessUplinks.derive { inherit site accessUnitNames compilerIndexes; }).byAccessUnit;
      allowedUplinksByScope = (accessUplinks.derive { inherit site accessUnitNames compilerIndexes; }).byScope;
      accessUnitByTenant = compilerIndexes.accessUnitByTenant;
      overlayNameSet = overlayNameSetFor site;

      # FS-210/FS-230: a public-ingress tuple whose target endpoint lives on an
      # access that declares no egress selection (a DMZ/namespace-authority
      # access that must not have WAN egress) still requires its ingress/return
      # lane, or the forwarded packet arrives with no return path. The target
      # access is the terminal hop of the tuple's modeled traffic path; derive
      # the lane from that, independently of the access's `selects`.
      publicIngressRelationIds =
        map (rel: rel.source.id or rel.id or null) (
          lib.filter
            (rel:
              builtins.isAttrs rel
              && (rel.action or "allow") == "allow"
              && builtins.isAttrs (rel.publicIngressTupleAuthority or null))
            (
              (site.communicationContract or { }).relations
              or (site.communicationContract or { }).allowedRelations
              or [ ]
            )
        );
      ingressTargetAccessUnits =
        let
          paths = lib.filter
            (p: builtins.elem (p.relationId or null) publicIngressRelationIds)
            (site.trafficPaths or [ ]);
          terminal =
            nodePath:
            if builtins.isList nodePath && nodePath != [ ] then toString (lib.last nodePath) else null;
          accessUnitSet = builtins.listToAttrs (
            map (u: {
              name = toString u;
              value = true;
            }) accessUnitNames
          );
          candidates = lib.concatMap (
            p:
            lib.unique (
              lib.filter (t: t != null) (
                map terminal ((p.nodePathAlternatives or [ ]) ++ [ (p.nodePath or [ ]) ])
              )
            )
          ) paths;
        in
        lib.unique (lib.filter (name: builtins.hasAttr name accessUnitSet) candidates);

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
          accessUnitByTenant
          allowedUplinksByScope
          canonicalP2pLinkNameForEndpointsWithSuffix
          downstreamSelectorUnit
          ingressTargetAccessUnits
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
