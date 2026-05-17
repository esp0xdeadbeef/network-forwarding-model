{ lib, self ? { outPath = ./.; }, ... }:

{
  derive =
    {
      site,
      accessUnitNames,
    }:
    let
      tenantsByAccessUnit =
        let
          attachments = site.attachments or [ ];
          step =
            acc: a:
            if !(builtins.isAttrs a) then
              acc
            else
              let
                unit = toString (a.unit or "");
                kind = toString (a.kind or "");
                name = toString (a.name or "");
              in
              if unit == "" || kind != "tenant" || name == "" then
                acc
              else
                acc // { "${unit}" = (acc.${unit} or [ ]) ++ [ name ]; };
        in
        builtins.foldl' step { } attachments;

      endpointTenantByName =
        let
          endpoints = site.ownership.endpoints or [ ];
          step =
            acc: endpoint:
            if !(builtins.isAttrs endpoint) then
              acc
            else
              let
                name = toString (endpoint.name or "");
                tenant = toString (endpoint.tenant or "");
              in
              if name == "" || tenant == "" then acc else acc // { "${name}" = tenant; };
        in
        builtins.foldl' step { } endpoints;

      serviceProviderTenants =
        serviceName:
        let
          services = site.communicationContract.services or site.services or [ ];
          matchingServices =
            lib.filter (
              service:
              builtins.isAttrs service && toString (service.name or "") == serviceName
            ) services;
          providerNames =
            lib.concatMap (
              service:
              if builtins.isList (service.providers or null) then map toString service.providers else [ ]
            ) matchingServices;
        in
        lib.unique (lib.filter (tenant: tenant != "") (
          map (provider: endpointTenantByName.${provider} or "") providerNames
        ));

      relationToUplinkNames =
        rel:
        let
          to = rel.to or { };
          kind = to.kind or null;
          uplinks = to.uplinks or null;
          name = to.name or null;
        in
        if kind != "external" then
          [ ]
        else if builtins.isList uplinks then
          map toString uplinks
        else if name != null && toString name != "" then
          [ (toString name) ]
        else
          [ ];

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

      allUplinkNames =
        let
          cores = site.upstreams.cores or { };
          names = lib.concatMap (
            coreName: map (u: toString (u.name or "")) (cores.${coreName} or [ ])
          ) (builtins.attrNames cores);
        in
        lib.sort (a: b: a < b) (lib.unique (lib.filter (s: s != "") names));

      allowedUplinksFor =
        unit:
        let
          relations = site.communicationContract.allowedRelations or [ ];
          hasAnyAllowRelation = lib.any (rel: (rel.action or null) == "allow") relations;
          uplinks =
            if !hasAnyAllowRelation then
              allUplinkNames
            else
              lib.concatMap (
                rel:
                if (rel.action or null) == "allow" && relationAppliesToAccessUnit unit rel then
                  relationToUplinkNames rel
                else
                  [ ]
              ) relations;
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
