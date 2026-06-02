{ lib }:

let
  cleanName = value: if value == null then "" else toString value;

  asList =
    value:
    if value == null then [ ] else if builtins.isList value then value else [ value ];

in
{
  build =
    { nodes
    , topo
    ,
    }:
    let
      accessUnitByTenant =
        builtins.foldl'
          (
            acc: attachment:
            if !(builtins.isAttrs attachment) || (attachment.kind or null) != "tenant" then
              acc
            else
              let
                tenantName = cleanName (attachment.name or null);
                unitName = cleanName (attachment.unit or null);
              in
              if tenantName == "" || unitName == "" then acc else acc // { "${tenantName}" = unitName; }
          )
          { }
          (topo.attachments or [ ]);

      endpointTenantByName =
        builtins.foldl'
          (
            acc: endpoint:
            if !(builtins.isAttrs endpoint) then
              acc
            else
              let
                endpointName = cleanName (endpoint.name or null);
                tenantName = cleanName (endpoint.tenant or null);
              in
              if endpointName == "" || tenantName == "" then acc else acc // { "${endpointName}" = tenantName; }
          )
          { }
          (topo.ownership.endpoints or [ ]);

      serviceProviderAccessUnits =
        serviceName:
        let
          services =
            if (topo.communicationContract or { }) ? services then
              topo.communicationContract.services
            else
              topo.services or [ ];
          matches =
            lib.filter
              (service: builtins.isAttrs service && cleanName (service.name or null) == serviceName)
              services;
          providers = lib.concatMap
            (service: map (provider: cleanName provider) (asList (service.providers or [ ])))
            matches;
        in
        lib.unique (
          lib.filter (unitName: unitName != "") (
            map
              (
                provider:
                let
                  tenantName = endpointTenantByName.${provider} or "";
                in
                if tenantName == "" then "" else accessUnitByTenant.${tenantName} or ""
              )
              providers
          )
        );

      sourceExternalUplinks =
        source:
        if (source.kind or null) != "external" then
          [ ]
        else if builtins.isList (source.uplinks or null) then
          map (uplink: cleanName uplink) source.uplinks
        else if (source.name or null) != null then
          [ (cleanName source.name) ]
        else
          [ ];

      accessUnitsInPath =
        path:
        lib.unique (
          lib.filter
            (nodeName: ((nodes.${nodeName} or { }).role or null) == "access")
            (map (nodeName: cleanName nodeName) path)
        );

      dnsServiceRouteScopes =
        path:
        if
          !(builtins.isAttrs path)
          || (path.action or null) != "allow"
          || (path.trafficType or null) != "dns"
          || ((path.destination or { }).kind or null) != "service"
        then
          [ ]
        else
          let
            serviceName = cleanName ((path.destination or { }).name or null);
            providerAccessUnits = serviceProviderAccessUnits serviceName;
            uplinks = sourceExternalUplinks (path.source or { });
            alternatives = path.nodePathAlternatives or [ (path.nodePath or [ ]) ];
            requesterAccessUnits =
              lib.filter
                (accessUnit: !(builtins.elem accessUnit providerAccessUnits))
                (lib.concatMap accessUnitsInPath alternatives);
          in
          if serviceName == "" || providerAccessUnits == [ ] || requesterAccessUnits == [ ] || uplinks == [ ] then
            [ ]
          else
            lib.concatMap
              (
                owner:
                lib.concatMap
                  (
                    access:
                    map
                      (uplink: {
                        inherit access owner serviceName uplink;
                      })
                      uplinks
                  )
                  requesterAccessUnits
              )
              providerAccessUnits;
    in
    builtins.foldl'
      (
        acc: scope:
        acc // {
          "${scope.owner}" = lib.unique (
            (acc.${scope.owner} or [ ])
            ++ [
              (builtins.removeAttrs scope [ "owner" ])
            ]
          );
        }
      )
      { }
      (lib.concatMap dnsServiceRouteScopes (topo.trafficPaths or [ ]));
}
