{ lib, ... }:

let
  addUnique =
    acc: name: value:
    acc // { "${name}" = lib.unique ((acc.${name} or [ ]) ++ [ value ]); };

  cleanName = value: if value == null then "" else toString value;
in
{
  build =
    {
      site,
    }:
    let
      endpointTenantByName = builtins.foldl' (
        acc: endpoint:
        if !(builtins.isAttrs endpoint) then
          acc
        else
          let
            name = cleanName (endpoint.name or "");
            tenant = cleanName (endpoint.tenant or "");
          in
          if name == "" || tenant == "" then acc else acc // { "${name}" = tenant; }
      ) { } (site.ownership.endpoints or [ ]);

      tenantsByAccessUnit = builtins.foldl' (
        acc: attachment:
        if !(builtins.isAttrs attachment) then
          acc
        else
          let
            unit = cleanName (attachment.unit or "");
            kind = cleanName (attachment.kind or "");
            name = cleanName (attachment.name or "");
          in
          if unit == "" || kind != "tenant" || name == "" then acc else addUnique acc unit name
      ) { } (site.attachments or [ ]);

      # FS-171: a tenant's serving access is the unit it attaches to for
      # client traffic. A tenant may also attach to other units (e.g. cores
      # that host its provider services), so map the tenant to the access-role
      # unit and never let a non-access unit overwrite it. Otherwise a tenant
      # attached to a core would resolve its lane to that core, and its core
      # return route and ingress/return lane would be lost.
      unitRole =
        unitName: ((site.nodes or { }).${unitName} or { }).role or ((site.topology.nodes or { }).${unitName} or { }).role or null;
      accessUnitByTenant = builtins.foldl' (
        acc: accessUnit:
        builtins.foldl' (
          tenantAcc: tenant:
          let
            existing = tenantAcc.${tenant} or null;
            isAccess = unitRole accessUnit == "access";
            existingIsAccess = existing != null && unitRole existing == "access";
          in
          if existing == null then
            tenantAcc // { "${tenant}" = accessUnit; }
          else if isAccess && !existingIsAccess then
            tenantAcc // { "${tenant}" = accessUnit; }
          else
            tenantAcc
        ) acc (tenantsByAccessUnit.${accessUnit} or [ ])
      ) { } (builtins.attrNames tenantsByAccessUnit);

      serviceProviderTenantsByName = builtins.foldl' (
        acc: service:
        if !(builtins.isAttrs service) then
          acc
        else
          let
            serviceName = cleanName (service.name or "");
            providerNames =
              if builtins.isList (service.providers or null) then map cleanName service.providers else [ ];
            # FS-210/FS-230: prefer the provider tenants the compiler resolved
            # from endpoint ownership; fall back to resolving endpoint names
            # from the endpoint->tenant index when it is present.
            declaredProviderTenants =
              if builtins.isList (service.providerTenants or null) then
                map cleanName service.providerTenants
              else
                [ ];
            providerTenants = lib.unique (
              lib.filter (tenant: tenant != "") (
                declaredProviderTenants
                ++ map (provider: endpointTenantByName.${provider} or "") providerNames
              )
            );
          in
          if serviceName == "" then acc else acc // { "${serviceName}" = providerTenants; }
      ) { } (site.communicationContract.services or site.services or [ ]);

      allUplinkNames =
        let
          # FS-322/FS-171: the exit surface names are owned by the topology
          # nodes that declare `uplinks`. Derive the full uplink name set from
          # those nodes; fall back to a compiler-emitted `upstreams.cores`
          # mapping when one is supplied.
          nodes = (site.topology or { }).nodes or { };
          fromNodes = lib.concatMap (
            nodeName:
            let
              u = (nodes.${nodeName} or { }).uplinks or { };
            in
            if builtins.isAttrs u then map (n: cleanName n) (builtins.attrNames u) else [ ]
          ) (builtins.attrNames nodes);
          cores = site.upstreams.cores or { };
          fromCores = lib.concatMap (coreName: map (u: cleanName (u.name or "")) (cores.${coreName} or [ ])) (
            builtins.attrNames cores
          );
          names = if fromCores != [ ] then fromCores else fromNodes;
        in
        lib.sort (a: b: a < b) (lib.unique (lib.filter (s: s != "") names));
    in
    {
      inherit
        accessUnitByTenant
        allUplinkNames
        endpointTenantByName
        serviceProviderTenantsByName
        tenantsByAccessUnit
        ;
    };
}
