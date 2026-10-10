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
      # access is the access that hosts the tuple's target service provider;
      # derive it from the relation's service provider tenants, independently of
      # the access's `selects` and of the (not-yet-computed) traffic paths.
      publicIngressRelations =
        lib.filter
          (rel:
            builtins.isAttrs rel
            && (rel.action or "allow") == "allow"
            && builtins.isAttrs (rel.publicIngressTupleAuthority or null))
          (
            (site.communicationContract or { }).relations
            or (site.communicationContract or { }).allowedRelations
            or [ ]
          );
      publicIngressRelationIds = map (rel: rel.source.id or rel.id or null) publicIngressRelations;
      ingressTargetAccessUnits =
        let
          accessUnitSet = builtins.listToAttrs (
            map (u: {
              name = toString u;
              value = true;
            }) accessUnitNames
          );
          providerTenantsFor =
            rel:
            let
              to = if builtins.isAttrs (rel.to or null) then rel.to else { };
              serviceName = toString (to.name or "");
              authority = if builtins.isAttrs (rel.publicIngressTupleAuthority or null) then rel.publicIngressTupleAuthority else { };
            in
            let
              declared = compilerIndexes.serviceProviderTenantsByName.${serviceName} or [ ];
              endpointTenant = compilerIndexes.endpointTenantByName.${toString (authority.targetEndpoint or "")} or null;
            in
            lib.unique (lib.filter (t: t != null) (declared ++ [ endpointTenant ]));
          fromProviders = lib.concatMap (
            rel:
            lib.filter (name: builtins.hasAttr name accessUnitSet) (
              map (tenant: toString (accessUnitByTenant.${tenant} or null)) (providerTenantsFor rel)
            )
          ) publicIngressRelations;
          # The tuple's modeled traffic path names the terminal target access;
          # include it when the paths are available so a target access that is
          # not a service provider is still covered.
          paths = lib.filter (
            p: builtins.elem (p.relationId or null) publicIngressRelationIds
          ) (site.trafficPaths or [ ]);
          terminal =
            nodePath:
            if builtins.isList nodePath && nodePath != [ ] then toString (lib.last nodePath) else null;
          fromPaths = lib.concatMap (
            p:
            lib.unique (
              lib.filter (t: t != null && builtins.hasAttr t accessUnitSet) (
                map terminal ((p.nodePathAlternatives or [ ]) ++ [ (p.nodePath or [ ]) ])
              )
            )
          ) paths;
        in
        lib.unique (fromProviders ++ fromPaths);

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
