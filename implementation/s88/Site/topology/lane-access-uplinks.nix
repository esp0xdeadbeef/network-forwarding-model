{
  lib,
  self ? {
    outPath = ./.;
  },
  ...
}:

let
  trafficPaths = import ./lane-access-uplinks/traffic-paths.nix { inherit lib self; };
  selectionMod = import ./lane-access-uplinks/selection.nix { inherit lib; };
in

{
  derive =
    {
      site,
      accessUnitNames,
      compilerIndexes,
    }:
    let
      inherit (compilerIndexes)
        allUplinkNames
        serviceProviderTenantsByName
        tenantsByAccessUnit
        ;

      serviceProviderTenants = serviceName: serviceProviderTenantsByName.${serviceName} or [ ];

      nodes = ((site.topology or { }).nodes or { }) // (site.nodes or { });

      selection = selectionMod.make {
        inherit
          nodes
          compilerIndexes
          allUplinkNames
          serviceProviderTenantsByName
          tenantsByAccessUnit
          serviceProviderTenants
          trafficPaths
          site
          accessUnitNames
          ;
      };
      inherit (selection)
        nodeUplinkNames
        selectsUplinksFor
        relationFromUplinkNames
        relationToUplinkNames
        trafficPathUplinksByAccessUnit
        relationAppliesToAccessUnit
        publicIngressTargetsAccessUnit
        ;

      allowedUplinksFor =
        unit:
        let
          relations = site.communicationContract.allowedRelations or [ ];
          hasAnyAllowRelation = lib.any (rel: (rel.action or null) == "allow") relations;
          compilerUplinks = trafficPathUplinksByAccessUnit.${unit} or [ ];
          # FS-210/FS-230 / FS-310-SMS-075: the target access's ingress/return
          # lane is keyed by the tuple's ingress surface. The surface is the
          # tuple authority's `publicSurface` when modeled, otherwise the
          # relation `from`'s external uplinks. This lane is ingress/return
          # transport only: it grants no exit selection, NAT/NAT66, or outbound
          # allow (FS-230-HDS-010-SDS-010).
          ingressSurfaceNamesFor =
            rel:
            let
              authority = if builtins.isAttrs (rel.publicIngressTupleAuthority or null) then rel.publicIngressTupleAuthority else { };
              publicSurface = authority.publicSurface or null;
              from = if builtins.isAttrs (rel.from or null) then rel.from else { };
              fromUplinks = if builtins.isList (from.uplinks or null) then map toString from.uplinks else [ ];
            in
            if publicSurface != null then
              [ (toString publicSurface) ]
            else
              fromUplinks;
          publicIngressUplinks = lib.concatMap (
            rel:
            if publicIngressTargetsAccessUnit unit rel then
              lib.filter (u: builtins.elem u allUplinkNames) (ingressSurfaceNamesFor rel)
            else
              [ ]
          ) relations;
          relationUplinks = lib.concatMap (
            rel:
            if (rel.action or null) == "allow" && relationAppliesToAccessUnit unit rel then
              relationToUplinkNames rel
            else
              [ ]
          ) relations;
          selectsUplinks = selectsUplinksFor unit;
          uplinks =
            if selectsUplinks != [ ] then
              selectsUplinks ++ publicIngressUplinks
            else if compilerUplinks != [ ] then
              compilerUplinks ++ publicIngressUplinks
            else if !hasAnyAllowRelation then
              allUplinkNames ++ publicIngressUplinks
            else
              relationUplinks ++ publicIngressUplinks;
        in
        lib.sort (a: b: a < b) (lib.unique (lib.filter (s: s != "") (map toString uplinks)));

      # FS-370 / FS-171: the lane identity is the **source scope** (a tenant or
      # access scope), not the access node. A tenant's reachability is its own
      # `selects`; the access unit is only the realization binding that carries
      # its ports. Two tenants on one access unit therefore get separate lane
      # sets, and adding an exit to a tenant's `selects` adds it to that tenant's
      # lane set only.
      #
      # For a tenant, the allowed uplinks are the union of:
      #   - the uplinks of the access scope the tenant attaches to (its selects),
      #   - the relations that grant that tenant external reachability, and
      #   - the public-ingress surfaces targeting services the tenant provides.
      allowedUplinksForTenant =
        tenant:
        let
          unit = compilerIndexes.accessUnitByTenant.${tenant} or null;
          unitUplinks = if unit == null then [ ] else allowedUplinksFor unit;
          relations = site.communicationContract.allowedRelations or [ ];
          tenantRelations = lib.filter (
            rel:
            (rel.action or null) == "allow"
            && (
              let
                from = rel.from or { };
                kind = from.kind or null;
              in
              (kind == "tenant" && toString (from.name or "") == tenant)
              || (
                kind == "tenant-set"
                && builtins.isList (from.members or null)
                && builtins.elem tenant (map toString from.members)
              )
            )
          ) relations;
          relationUplinks = lib.concatMap relationToUplinkNames tenantRelations;
          publicIngressUplinks = lib.concatMap (
            rel:
            if
              (rel.action or null) == "allow"
              && builtins.isAttrs (rel.publicIngressTupleAuthority or null)
              && (rel.from or { }).kind or null == "external"
              && (rel.to or { }).kind or null == "service"
              && builtins.elem tenant (serviceProviderTenants (toString ((rel.to or { }).name or "")))
            then
              # FS-210/FS-230: the provider's public surface is named by the
              # tuple authority (`publicSurface`), not by `from` (which names the
              # external source scope). The service endpoint's tenant still needs
              # the ingress/return transport lane to its access, keyed by the
              # provider scope; this adds the lane, not egress authority (the
              # tenant declares no `selects`).
              let
                surface = (rel.publicIngressTupleAuthority or { }).publicSurface or null;
              in
              if surface == null then
                [ ]
              else if builtins.elem (toString surface) allUplinkNames then
                [ (toString surface) ]
              else
                nodeUplinkNames (toString surface)
            else
              [ ]
          ) relations;
        in
        lib.sort (a: b: a < b) (
          # A public-ingress surface is NOT an egress uplink. Adding it here made
          # the scope look like an egress access, so the downstream-selector/
          # policy installed a default route instead of the served tenant
          # prefix, and the dedicated ingress/return lane (selector-lanes.nix,
          # uplink=null) was skipped. The ingress/return lane is derived
          # independently from the tuple's traffic path.
          lib.unique (lib.filter (s: s != "") (map toString (unitUplinks ++ relationUplinks)))
        );

      tenantScopeNames = builtins.attrNames compilerIndexes.accessUnitByTenant;
    in
    {
      byAccessUnit = builtins.listToAttrs (
        map (unit: {
          name = unit;
          value = allowedUplinksFor unit;
        }) accessUnitNames
      );
      byScope = builtins.listToAttrs (
        map (tenant: {
          name = tenant;
          value = allowedUplinksForTenant tenant;
        }) tenantScopeNames
      );
    };
}
