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

  tenantIpv4ByName =
    site:
    builtins.listToAttrs (
      map (tenant: {
        name = toString tenant.name;
        value = if tenant.ipv4 or null != null then toString tenant.ipv4 else null;
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
        ++ (if (to.name or null) != null then [ (toString to.name) ] else [ ]);
    in
    (to.kind or null) == "external" && builtins.elem uplinkName uplinks;

  validNat44Modes = [ "nat44" "masquerade" "snat" ];

  isHostOnlyProviderPrefix =
    tenantPrefixOwners: prefix:
    let
      key = "4|${toString prefix}";
      owner = tenantPrefixOwners.${key} or null;
    in
    owner != null && (owner.authorityClass or null) == "host-only-provider-prefix";
in
{
  forUplinks =
    site: uplinkNames: uplinks:
    let
      contract = attrsOrEmpty (site.communicationContract or null);
      relations =
        if builtins.isList (contract.relations or null) then
          contract.relations
        else
          listOrEmpty (contract.allowedRelations or null);
      tenantPrefixes = tenantIpv4ByName site;
      tenantPrefixOwners = attrsOrEmpty (site.tenantPrefixOwners or null);
      intentForUplink =
        uplinkName:
        let
          uplink = attrsOrEmpty (uplinks.${uplinkName} or null);
          translation = attrsOrEmpty (
            (attrsOrEmpty ((attrsOrEmpty (uplink.egress or null)).ipv4 or null)).translation or null
          );
          mode = translation.mode or null;
          enabled = mode != null && builtins.elem mode validNat44Modes;
          sourceTenantNames = sortedUnique (
            builtins.concatMap (
              relation:
              if (relation.action or "allow") == "allow" && relationTargetsUplink uplinkName relation then
                endpointTenantNames site (relation.from or null)
              else
                [ ]
            ) relations
          );
          allSourcePrefixes = sortedUnique (
            map (tenantName: tenantPrefixes.${tenantName} or null) sourceTenantNames
          );
          # FS-380-HDS-010-SDS-010-SMS-040: filter out host-only-provider-prefix
          sourcePrefixes = builtins.filter (p: !(isHostOnlyProviderPrefix tenantPrefixOwners p)) allSourcePrefixes;
          hostOnlyFiltered = builtins.filter (p: isHostOnlyProviderPrefix tenantPrefixOwners p) allSourcePrefixes;
          egressSurfaceName = uplinkName;
        in
        if !enabled then
          null
        else if sourcePrefixes == [ ] then
          null
        else
          {
            name = uplinkName;
            value = {
              mode = mode;
              sourcePrefixes = sourcePrefixes;
              egressSurface = egressSurfaceName;
            }
            // lib.optionalAttrs (hostOnlyFiltered != [ ]) {
              hostOnlyFiltered = hostOnlyFiltered;
            }
            // lib.optionalAttrs ((translation.warning or null) != null) {
              warning = toString translation.warning;
            };
          };
      entries = builtins.filter (entry: entry != null) (map intentForUplink uplinkNames);
    in
    if entries == [ ] then { } else builtins.listToAttrs entries;
}
