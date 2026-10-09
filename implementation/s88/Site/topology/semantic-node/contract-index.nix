# Contract indexes for NAT66 egress resolution, split out of nat66-egress.nix so
# that module stays under the tracked LOC soft limit.
{
  lib,
  sortedUnique,
  listOrEmpty,
  attrsOrEmpty,
}:

let
  normalizedTenants =
    site:
    let
      tenants = (attrsOrEmpty (site.domains or null)).tenants or [ ];
    in
    if builtins.isList tenants then
      builtins.filter (tenant: builtins.isAttrs tenant && (tenant.name or null) != null) tenants
    else if builtins.isAttrs tenants then
      lib.mapAttrsToList (
        name: tenant: (attrsOrEmpty tenant) // { name = toString ((attrsOrEmpty tenant).name or name); }
      ) tenants
    else
      [ ];

  tenantIpv6ByName =
    site:
    builtins.listToAttrs (
      map (tenant: {
        name = toString tenant.name;
        value = if tenant.ipv6 or null != null then toString tenant.ipv6 else null;
      }) (normalizedTenants site)
    );

  endpointTenantsByName =
    site:
    builtins.listToAttrs (
      map
        (endpoint: {
          name = toString endpoint.name;
          value = endpoint.tenant or null;
        })
        (
          builtins.filter (
            endpoint:
            builtins.isAttrs endpoint && (endpoint.name or null) != null && (endpoint.tenant or null) != null
          ) (listOrEmpty ((attrsOrEmpty (site.ownership or null)).endpoints or null))
        )
    );

  servicesByName =
    site:
    builtins.listToAttrs (
      map
        (service: {
          name = toString service.name;
          value = service;
        })
        (
          builtins.filter (service: builtins.isAttrs service && (service.name or null) != null) (
            listOrEmpty ((attrsOrEmpty (site.communicationContract or null)).services or null)
          )
        )
    );

  endpointTenantNames =
    site: endpoint:
    let
      ep = attrsOrEmpty endpoint;
      serviceMap = servicesByName site;
      endpointTenantMap = endpointTenantsByName site;
      providerTenants =
        service:
        sortedUnique (
          map (provider: endpointTenantMap.${provider} or null) (listOrEmpty (service.providers or null))
        );
    in
    if (ep.kind or null) == "tenant" && (ep.name or null) != null then
      [ (toString ep.name) ]
    else if (ep.kind or null) == "tenant-set" then
      sortedUnique (listOrEmpty (ep.members or null))
    else if
      (ep.kind or null) == "service" && (ep.name or null) != null && builtins.hasAttr ep.name serviceMap
    then
      providerTenants serviceMap.${ep.name}
    else
      [ ];

  relationTargetsUplink =
    uplinkName: relation:
    let
      to = attrsOrEmpty (relation.to or null);
      uplinks =
        (listOrEmpty (to.uplinks or null))
        ++ (if (to.scope or null) != null then [ (toString to.scope) ] else [ ])
        ++ (if (to.name or null) != null then [ (toString to.name) ] else [ ]);
    in
    (to.kind or null) == "external" && builtins.elem uplinkName uplinks;
in
{
  inherit
    normalizedTenants
    tenantIpv6ByName
    endpointTenantsByName
    servicesByName
    endpointTenantNames
    relationTargetsUplink
    ;
}
