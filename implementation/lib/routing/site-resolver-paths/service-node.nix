{ lib }:

# Service-to-provider-node resolution for the resolver path.
#
# The compiler's `services` list is the authoritative service -> provider map
# (`providerNode` for a node-hosted service such as the core resolver,
# `providers`/`providerTenants` for an endpoint-hosted one). `ownership.endpoints`
# is keyed by endpoint name, not service name, so a focused fixture without a
# `services` list still resolves through the endpoint -> tenant -> attachment
# chain. Looking a service up only in `ownership.endpoints` returned no node for
# a real site and downstream stages then invented the hop.
let
  attrsOrEmpty = a: if builtins.isAttrs a then a else { };
  listOrEmpty = v: if builtins.isList v then v else [ ];

  endpointTenantByName =
    site:
    builtins.foldl'
      (
        acc: endpoint:
        let
          name = toString (endpoint.name or "");
          tenant = toString (endpoint.tenant or "");
        in
        if name == "" || tenant == "" then acc else acc // { "${name}" = tenant; }
      )
      { }
      (listOrEmpty ((attrsOrEmpty (site.ownership or { })).endpoints or [ ]));

  accessUnitByTenant =
    site:
    let
      nodes = attrsOrEmpty (site.nodes or { });
    in
    builtins.foldl'
      (
        acc: nodeName:
        builtins.foldl'
          (
            acc2: attachment:
            let
              kind = attachment.kind or null;
              name = toString (attachment.name or "");
            in
            if kind == "tenant" && name != "" then acc2 // { "${name}" = nodeName; } else acc2
          )
          acc
          (listOrEmpty ((attrsOrEmpty (nodes.${nodeName} or null)).attachments or [ ]))
      )
      { }
      (builtins.attrNames nodes);

  nodeForService =
    site: serviceName:
    let
      tenants = endpointTenantByName site;
      accessByTenant = accessUnitByTenant site;
      nodes = attrsOrEmpty (site.nodes or { });
      services = if builtins.isList (site.services or null) then site.services else [ ];
      serviceRecord = lib.findFirst
        (
          service: builtins.isAttrs service && toString (service.name or "") == serviceName
        )
        null
        services;
      providerNode = (attrsOrEmpty serviceRecord).providerNode or null;
      providerTenantNames =
        let
          direct = listOrEmpty ((attrsOrEmpty serviceRecord).providerTenants or [ ]);
        in
        if direct != [ ] then
          map toString direct
        else
          lib.unique (
            map (provider: tenants.${toString provider} or "") (
              listOrEmpty ((attrsOrEmpty serviceRecord).providers or [ ])
            )
          );
      providerNodes = lib.unique (
        map (tenantName: accessByTenant.${tenantName} or "") (
          builtins.filter (tenantName: tenantName != "") providerTenantNames
        )
      );
      endpointTenant = tenants.${serviceName} or null;
      endpointNode =
        if endpointTenant != null && builtins.hasAttr endpointTenant accessByTenant then
          accessByTenant.${endpointTenant}
        else
          null;
      directMatch = builtins.filter
        (
          nodeName:
          builtins.any (a: (a.kind or null) == "tenant" && (a.name or null) == serviceName) (
            listOrEmpty ((attrsOrEmpty (nodes.${nodeName} or null)).attachments or [ ])
          )
        )
        (builtins.attrNames nodes);
    in
    if providerNode != null then
      providerNode
    else if providerNodes != [ ] then
      builtins.head providerNodes
    else if endpointNode != null then
      endpointNode
    else if directMatch != [ ] then
      builtins.head directMatch
    else
      null;
in
{
  inherit
    accessUnitByTenant
    endpointTenantByName
    nodeForService
    ;
}
