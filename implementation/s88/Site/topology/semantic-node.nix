{
  lib,
  self ? {
    outPath = ./.;
  },
  ...
}:

let
  roleCapabilities = import ./role-capabilities.nix { };

  sortedUnique =
    xs:
    lib.sort (a: b: toString a < toString b) (lib.unique (map toString (lib.filter (x: x != null) xs)));
  listOrEmpty = value: if builtins.isList value then value else [ ];
  attrsOrEmpty = value: if builtins.isAttrs value then value else { };

  ifaceUplinkName =
    iface:
    if builtins.isAttrs iface && iface ? uplink && iface.uplink != null then
      toString iface.uplink
    else if builtins.isAttrs iface && iface ? upstream && iface.upstream != null then
      toString iface.upstream
    else
      null;

  wanInterfacesForNode =
    node:
    let
      interfaces = node.interfaces or { };
      names = builtins.attrNames interfaces;
    in
    sortedUnique (
      lib.filter (
        ifName:
        let
          iface = interfaces.${ifName};
          kind = iface.kind or null;
          carrier = iface.carrier or null;
          type = iface.type or null;
        in
        kind == "wan" || carrier == "wan" || type == "wan"
      ) names
    );

  declaredUplinksForNode =
    node:
    if node ? uplinks && builtins.isAttrs node.uplinks then
      sortedUnique (builtins.attrNames node.uplinks)
    else
      [ ];

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
        ++ (if (to.name or null) != null then [ (toString to.name) ] else [ ]);
    in
    (to.kind or null) == "external" && builtins.elem uplinkName uplinks;

  nat66IntentForUplinks =
    site: uplinkNames: uplinks:
    let
      contract = attrsOrEmpty (site.communicationContract or null);
      relations =
        if builtins.isList (contract.relations or null) then
          contract.relations
        else
          listOrEmpty (contract.allowedRelations or null);
      tenantPrefixes = tenantIpv6ByName site;
      intentForUplink =
        uplinkName:
        let
          uplink = attrsOrEmpty (uplinks.${uplinkName} or null);
          translation = attrsOrEmpty (
            (attrsOrEmpty ((attrsOrEmpty (uplink.egress or null)).ipv6 or null)).translation or null
          );
          enabled = (translation.mode or null) == "nat66";
          sourceTenantNames = sortedUnique (
            builtins.concatMap (
              relation:
              if (relation.action or "allow") == "allow" && relationTargetsUplink uplinkName relation then
                endpointTenantNames site (relation.from or null)
              else
                [ ]
            ) relations
          );
          sourcePrefixes = sortedUnique (
            map (tenantName: tenantPrefixes.${tenantName} or null) sourceTenantNames
          );
        in
        if !enabled then
          null
        else
          {
            name = uplinkName;
            value = {
              mode = "nat66";
              sourcePrefixes = sourcePrefixes;
            }
            // lib.optionalAttrs ((translation.warning or null) != null) {
              warning = toString translation.warning;
            };
          };
      entries = builtins.filter (entry: entry != null) (map intentForUplink uplinkNames);
    in
    if entries == [ ] then { } else builtins.listToAttrs entries;

  build =
    {
      nodeName,
      node,
      site,
      role,
      siteUplinkCoreNames,
      siteUplinkNames,
      siteExternalDomains,
    }:
    let
      exitNode = lib.elem nodeName siteUplinkCoreNames;
      upstreamSelection = role == "upstream-selector";
      eligible = exitNode || upstreamSelection;

      wanIfaces = wanInterfacesForNode node;
      interfaces = node.interfaces or { };

      interfaceUplinks = sortedUnique (map (ifName: ifaceUplinkName interfaces.${ifName}) wanIfaces);
      nodeSpecificUplinks = sortedUnique ((declaredUplinksForNode node) ++ interfaceUplinks);
      eligibleUplinks = if nodeSpecificUplinks != [ ] then nodeSpecificUplinks else siteUplinkNames;
      nat66ByUplink = nat66IntentForUplinks site eligibleUplinks (attrsOrEmpty (node.uplinks or null));

      effectiveUplinks = if eligible then eligibleUplinks else sortedUnique interfaceUplinks;
      effectiveWanInterfaces =
        if wanIfaces != [ ] then
          wanIfaces
        else if eligible then
          eligibleUplinks
        else
          [ ];

      capabilityArgs = {
        inherit exitNode role upstreamSelection;
      };
    in
    {
      egressIntent = {
        eligible = eligible;
        exit = exitNode;
        explicit = true;
        externalDomains = if eligible then siteExternalDomains else [ ];
        nat66 = nat66ByUplink;
        uplinks = effectiveUplinks;
        upstreamSelection = upstreamSelection;
        wanInterfaces = effectiveWanInterfaces;
      };

      forwardingFunctions = roleCapabilities.forwardingFunctionsFor capabilityArgs;
      forwardingResponsibility = roleCapabilities.forwardingResponsibilityFor capabilityArgs;
      routingAuthority = roleCapabilities.routingAuthorityFor capabilityArgs;
      traversalParticipation = roleCapabilities.traversalParticipationFor capabilityArgs;
    };

in
{
  inherit build;
}
