# FS-322 selection and uplink-resolution helpers, split out of
# lane-access-uplinks.nix so that module stays under the tracked LOC soft limit.
{ lib }:

{
  make =
    {
      nodes,
      compilerIndexes,
      allUplinkNames,
      serviceProviderTenantsByName,
      tenantsByAccessUnit,
      serviceProviderTenants,
      trafficPaths,
      site,
      accessUnitNames,
    }:
    let
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
    in
    {
      inherit
        nodeUplinkNames
        selectUplinkNames
        selectsUplinksFor
        endpointUplinkNames
        relationToUplinkNames
        relationFromUplinkNames
        trafficPathUplinksByAccessUnit
        relationAppliesToAccessUnit
        publicIngressTargetsAccessUnit
        ;
    };
}
