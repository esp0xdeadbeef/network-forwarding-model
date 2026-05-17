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

      accessUnitByTenant =
        builtins.foldl' (
          acc: accessUnit:
          builtins.foldl' (
            tenantAcc: tenant:
            tenantAcc // { "${tenant}" = toString accessUnit; }
          ) acc (tenantsByAccessUnit.${accessUnit} or [ ])
        ) { } (builtins.attrNames tenantsByAccessUnit);

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

      sourceAccessUnits =
        source:
        let
          kind = source.kind or null;
        in
        if kind == "tenant" then
          let
            tenantName = toString (source.name or "");
            accessUnit = accessUnitByTenant.${tenantName} or null;
          in
          if accessUnit == null then [ ] else [ accessUnit ]
        else if kind == "tenant-set" then
          let
            members = if builtins.isList (source.members or null) then map toString source.members else [ ];
          in
          lib.unique (lib.filter (x: x != null) (map (tenant: accessUnitByTenant.${tenant} or null) members))
        else
          [ ];

      pathAccessUnits =
        path:
        lib.filter (
          nodeName: builtins.elem nodeName accessUnitNames
        ) (map toString path);

      pathUplinks =
        path:
        let
          pathSet = builtins.listToAttrs (map (nodeName: { name = toString nodeName; value = true; }) path);
          cores = site.upstreams.cores or { };
          coreNames = builtins.attrNames cores;
          matchingCores = lib.filter (coreName: builtins.hasAttr coreName pathSet) coreNames;
        in
        lib.concatMap (
          coreName:
          map (u: toString (u.name or "")) (cores.${coreName} or [ ])
        ) matchingCores;

      trafficPathEntries =
        let
          trafficPaths = site.trafficPaths or [ ];
          perPath =
            path:
            if !(builtins.isAttrs path) || (path.action or "allow") != "allow" then
              [ ]
            else
              let
                destination = path.destination or { };
                destinationUplinks =
                  if (destination.kind or null) != "external" then
                    [ ]
                  else if builtins.isList (destination.uplinks or null) then
                    map toString destination.uplinks
                  else if (destination.name or null) != null then
                    [ (toString destination.name) ]
                  else
                    [ ];
                alternatives = path.nodePathAlternatives or [ (path.nodePath or [ ]) ];
                sourceUnits = sourceAccessUnits (path.source or { });
                accessUnits =
                  if sourceUnits != [ ] then
                    sourceUnits
                  else
                    lib.concatMap pathAccessUnits alternatives;
                uplinks =
                  if destinationUplinks != [ ] then
                    destinationUplinks
                  else
                    lib.concatMap pathUplinks alternatives;
              in
              lib.concatMap (
                accessUnit:
                map (uplinkName: {
                  inherit accessUnit uplinkName;
                }) uplinks
              ) accessUnits;
        in
        lib.concatMap perPath trafficPaths;

      trafficPathUplinksByAccessUnit =
        builtins.foldl' (
          acc: entry:
          if (entry.accessUnit or "") == "" || (entry.uplinkName or "") == "" then
            acc
          else
            acc // {
              "${entry.accessUnit}" = (acc.${entry.accessUnit} or [ ]) ++ [ entry.uplinkName ];
            }
        ) { } trafficPathEntries;

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
          compilerUplinks = trafficPathUplinksByAccessUnit.${unit} or [ ];
          uplinks =
            if compilerUplinks != [ ] then
              compilerUplinks
            else if !hasAnyAllowRelation then
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
