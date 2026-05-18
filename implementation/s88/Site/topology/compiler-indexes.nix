{ lib, ... }:

let
  addUnique = acc: name: value:
    acc // { "${name}" = lib.unique ((acc.${name} or [ ]) ++ [ value ]); };

  cleanName = value: if value == null then "" else toString value;
in
{
  build =
    {
      site,
    }:
    let
      endpointTenantByName =
        builtins.foldl' (
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

      tenantsByAccessUnit =
        builtins.foldl' (
          acc: attachment:
          if !(builtins.isAttrs attachment) then
            acc
          else
            let
              unit = cleanName (attachment.unit or "");
              kind = cleanName (attachment.kind or "");
              name = cleanName (attachment.name or "");
            in
            if unit == "" || kind != "tenant" || name == "" then
              acc
            else
              addUnique acc unit name
        ) { } (site.attachments or [ ]);

      accessUnitByTenant =
        builtins.foldl' (
          acc: accessUnit:
          builtins.foldl' (
            tenantAcc: tenant:
            tenantAcc // { "${tenant}" = accessUnit; }
          ) acc (tenantsByAccessUnit.${accessUnit} or [ ])
        ) { } (builtins.attrNames tenantsByAccessUnit);

      serviceProviderTenantsByName =
        builtins.foldl' (
          acc: service:
          if !(builtins.isAttrs service) then
            acc
          else
            let
              serviceName = cleanName (service.name or "");
              providerNames =
                if builtins.isList (service.providers or null) then map cleanName service.providers else [ ];
              providerTenants = lib.unique (
                lib.filter (tenant: tenant != "") (
                  map (provider: endpointTenantByName.${provider} or "") providerNames
                )
              );
            in
            if serviceName == "" then acc else acc // { "${serviceName}" = providerTenants; }
        ) { } (site.communicationContract.services or site.services or [ ]);

      allUplinkNames =
        let
          cores = site.upstreams.cores or { };
          names = lib.concatMap (
            coreName: map (u: cleanName (u.name or "")) (cores.${coreName} or [ ])
          ) (builtins.attrNames cores);
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
