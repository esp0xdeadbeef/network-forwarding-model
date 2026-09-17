{
  lib,
  self ? {
    outPath = ./.;
  },
  ...
}:

let
  trafficPaths = import ./lane-access-uplinks/traffic-paths.nix { inherit lib self; };
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
      nodeUplinkNames =
        nodeName:
        let
          u = (nodes.${nodeName} or { }).uplinks or { };
        in
        builtins.attrNames (if builtins.isAttrs u then u else { });

      # FS-322: a scope declares its reachability with `selects`. An entry is a
      # string (uplink name) or `{ uplink = "..."; }` / `{ scope = "..."; }`.
      # A selected scope resolves to that scope's own uplinks (or itself when it
      # is itself an exit surface).
      selectUplinkNames =
        entry:
        if builtins.isString entry then
          [ entry ]
        else if builtins.isAttrs entry then
          let
            up = entry.uplink or null;
            surface = entry.surface or null;
            sc = entry.scope or null;
          in
          # Prefer the declared surface (a specific uplink/exit) so a selection
          # that names one surface is not widened to every uplink the owning
          # scope hosts; fall back to the owning scope's uplinks.
          if up != null then
            [ (toString up) ]
          else if surface != null && builtins.elem (toString surface) allUplinkNames then
            [ (toString surface) ]
          else if sc != null then
            if builtins.elem (toString sc) allUplinkNames then
              [ (toString sc) ]
            else
              nodeUplinkNames (toString sc)
          else
            [ ]
        else
          [ ];

      selectsUplinksFor =
        unit:
        let
          sel = (nodes.${unit} or { }).selects or [ ];
        in
        if builtins.isList sel then lib.concatMap selectUplinkNames sel else [ ];

      endpointUplinkNames =
        ep:
        let
          kind = ep.kind or null;
          uplinks = ep.uplinks or null;
          scope = ep.scope or null;
          name = ep.name or null;
        in
        if kind != "external" then
          [ ]
        else if builtins.isList uplinks then
          map toString uplinks
        else if scope != null && toString scope != "" then
          if builtins.elem (toString scope) allUplinkNames then
            [ (toString scope) ]
          else
            nodeUplinkNames (toString scope)
        else if name != null && toString name != "" then
          [ (toString name) ]
        else
          [ ];

      relationToUplinkNames = rel: endpointUplinkNames (rel.to or { });

      relationFromUplinkNames = rel: endpointUplinkNames (rel.from or { });

      trafficPathUplinksByAccessUnit = trafficPaths.uplinksByAccessUnit {
        inherit
          compilerIndexes
          site
          accessUnitNames
          ;
      };

      relationAppliesToAccessUnit =
        unit: rel:
        let
          from = rel.from or { };
          unitTenants = tenantsByAccessUnit.${unit} or [ ];
          kind = from.kind or null;
        in
        if kind == "tenant" then
          builtins.elem (toString (from.name or "")) unitTenants
        else if kind == "tenant-set" then
          let
            members = if builtins.isList (from.members or null) then map toString from.members else [ ];
          in
          lib.any (t: builtins.elem t members) unitTenants
        else if kind == "service" then
          let
            providerTenants = serviceProviderTenants (toString (from.name or ""));
          in
          lib.any (tenant: builtins.elem tenant unitTenants) providerTenants
        else
          false;

      publicIngressTargetsAccessUnit =
        unit: rel:
        let
          from = rel.from or { };
          to = rel.to or { };
          authority = rel.publicIngressTupleAuthority or null;
          serviceName = toString (to.name or "");
          providerTenants = serviceProviderTenants serviceName;
          unitTenants = tenantsByAccessUnit.${unit} or [ ];
        in
        (rel.action or null) == "allow"
        && builtins.isAttrs authority
        && (from.kind or null) == "external"
        && (to.kind or null) == "service"
        && serviceName != ""
        && lib.any (tenant: builtins.elem tenant unitTenants) providerTenants;

      allowedUplinksFor =
        unit:
        let
          relations = site.communicationContract.allowedRelations or [ ];
          hasAnyAllowRelation = lib.any (rel: (rel.action or null) == "allow") relations;
          compilerUplinks = trafficPathUplinksByAccessUnit.${unit} or [ ];
          publicIngressUplinks = lib.concatMap (
            rel: if publicIngressTargetsAccessUnit unit rel then relationFromUplinkNames rel else [ ]
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
              relationFromUplinkNames rel
            else
              [ ]
          ) relations;
        in
        lib.sort (a: b: a < b) (
          lib.unique (lib.filter (s: s != "") (map toString (unitUplinks ++ relationUplinks ++ publicIngressUplinks)))
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
