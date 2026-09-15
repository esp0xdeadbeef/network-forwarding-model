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

      nodes = (site.topology or { }).nodes or { };
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
            sc = entry.scope or null;
          in
          if up != null then
            [ (toString up) ]
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
    in
    builtins.listToAttrs (
      map (unit: {
        name = unit;
        value = allowedUplinksFor unit;
      }) accessUnitNames
    );
}
