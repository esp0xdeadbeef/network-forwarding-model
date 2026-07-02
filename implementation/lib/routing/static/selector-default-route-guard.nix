{ lib, self ? { outPath = ./.; }, ... }:

let
  link = import (self.outPath + "/implementation/lib/topology/link-utils.nix") { inherit lib self; };
  defaultRoutePolicy = import (self.outPath + "/implementation/lib/routing/default-route-policy.nix") { inherit lib; };
  helpers = import (self.outPath + "/implementation/lib/routing/static-helpers.nix") { inherit lib self; };
  routeContext = import (self.outPath + "/implementation/lib/routing/route-context.nix") { inherit lib self; };

  sortedUnique = xs: lib.sort (a: b: toString a < toString b) (lib.unique (map toString xs));
  roleOf = nodes: nodeName: (nodes.${nodeName} or { }).role or null;

  isDefaultRoute =
    route:
    (route.intent.kind or null) == "default-reachability"
    || (
      (route.proto or null) == "default"
      && ((route.dst or null) == helpers.default4 || (route.dst or null) == helpers.default6)
    );

  ifaceRoutes =
    iface:
    let routes = iface.routes or { };
    in (routes.ipv4 or [ ]) ++ (routes.ipv6 or [ ]) ++ (iface.routes4 or [ ]) ++ (iface.routes6 or [ ]);

  coreNodeNamesFor =
    topo:
    let nodes = topo.nodes or { };
    in
    if builtins.isList (topo.coreNodeNames or null) && topo.coreNodeNames != [ ] then
      sortedUnique topo.coreNodeNames
    else
      sortedUnique (lib.filter (nodeName: roleOf nodes nodeName == "core") (builtins.attrNames nodes));

  upstreamSelectorFor =
    topo:
    let
      nodes = topo.nodes or { };
      explicit = topo.upstreamSelectorNodeName or null;
      inferred = lib.filter (nodeName: roleOf nodes nodeName == "upstream-selector") (builtins.attrNames nodes);
    in
    if explicit != null then toString explicit else if inferred == [ ] then null else builtins.head (sortedUnique inferred);

  tenantsForAccess =
    topo: accessName:
    sortedUnique (
      lib.filter (tenant: tenant != null) (
        map
          (
            attachment:
            if
              (attachment.kind or null) == "tenant"
              && (attachment.unit or null) != null
              && toString attachment.unit == accessName
            then
              attachment.name or null
            else
              null
          )
          (topo.attachments or [ ])
      )
    );

  linkUplinkNames =
    linkObj:
    let
      meta = if builtins.isAttrs (linkObj.laneMeta or null) then linkObj.laneMeta else { };
      fromList = if builtins.isList (linkObj.uplinks or null) then linkObj.uplinks else [ ];
      fromMeta =
        if meta.uplink or null != null then [ meta.uplink ]
        else if builtins.isList (meta.uplinks or null) then meta.uplinks
        else [ ];
      fromAttrs =
        lib.optional ((linkObj.uplink or null) != null) linkObj.uplink
        ++ lib.optional ((linkObj.upstream or null) != null) linkObj.upstream;
    in
    sortedUnique (fromList ++ fromMeta ++ fromAttrs);

  linksForSelectorCoreUplink =
    topo: upstreamSelectorName: coreSet: uplinkName:
    let
      links = topo.links or { };
      connectsSelectorAndCore =
        linkName:
        let members = link.membersOf (links.${linkName} or { });
        in
        builtins.elem upstreamSelectorName members
        && builtins.any (member: coreSet.${toString member} or false) members;
      uplinkMatches =
        linkName:
        let names = linkUplinkNames (links.${linkName} or { });
        in names == [ ] || builtins.elem uplinkName names;
    in
    lib.filter (linkName: connectsSelectorAndCore linkName && uplinkMatches linkName) (builtins.attrNames links);

  selectorDefaultRoutes =
    selectorNode:
    let interfaces = selectorNode.interfaces or { };
    in
    lib.concatMap
      (
        ifName:
        map
          (route: {
            inherit ifName route;
          })
          (lib.filter isDefaultRoute (ifaceRoutes (interfaces.${ifName} or { })))
      )
      (builtins.attrNames interfaces);

  formatPair =
    pair:
    let tenants = if pair.tenants == [ ] then "<unknown-tenant>" else builtins.concatStringsSep "," pair.tenants;
    in "access=${pair.accessName} tenant=${tenants} uplink=${pair.uplinkName}";

in
{
  validate =
    topo:
    let
      nodes = topo.nodes or { };
      upstreamSelectorName = upstreamSelectorFor topo;
      selectorNode = if upstreamSelectorName == null then { } else nodes.${upstreamSelectorName} or { };
      coreNodeNames = coreNodeNamesFor topo;
      coreSet = lib.listToAttrs (map (name: { inherit name; value = true; }) coreNodeNames);
      accessNodeNames = sortedUnique (
        lib.filter (nodeName: roleOf nodes nodeName == "access") (builtins.attrNames nodes)
      );
      defaultUplinkSet = (routeContext.buildFacts topo).uplinkHasDefaultSet or { };
      overlayUplinkSet = (routeContext.buildFacts topo).overlayUplinkNameSet or { };
      egressRequirements =
        lib.concatMap
          (
            accessName:
            map
              (uplinkName: {
                inherit accessName uplinkName;
                tenants = tenantsForAccess topo accessName;
              })
              (
                lib.filter
                  (uplinkName: builtins.hasAttr uplinkName defaultUplinkSet && !(builtins.hasAttr uplinkName overlayUplinkSet))
                  (defaultRoutePolicy.anyTrafficDefaultUplinksForAccess topo accessName)
              )
          )
          accessNodeNames;

      defaults = selectorDefaultRoutes selectorNode;
      links = topo.links or { };
      connectsSelectorToCore =
        ifName:
        let members = link.membersOf (links.${ifName} or { });
        in
        upstreamSelectorName != null
        && builtins.elem upstreamSelectorName members
        && builtins.any (member: coreSet.${toString member} or false) members;

      bypasses = lib.filter (item: !(connectsSelectorToCore item.ifName)) defaults;
      firstBypass = if bypasses == [ ] then null else builtins.head bypasses;
      bypassAccess = if firstBypass == null then null else firstBypass.route.lane.access or null;
      bypassTenants = if bypassAccess == null then [ ] else tenantsForAccess topo (toString bypassAccess);
      bypassTenantText = if bypassTenants == [ ] then "<unknown-tenant>" else builtins.concatStringsSep "," bypassTenants;

      hasCoreDefaultFor =
        requirement:
        builtins.any
          (
            linkName:
            builtins.any isDefaultRoute (ifaceRoutes ((selectorNode.interfaces or { }).${linkName} or { }))
          )
          (linksForSelectorCoreUplink topo upstreamSelectorName coreSet requirement.uplinkName);

      missing = lib.filter (requirement: !(hasCoreDefaultFor requirement)) egressRequirements;
      firstMissing = if missing == [ ] then null else builtins.head missing;
    in
    if upstreamSelectorName == null || egressRequirements == [ ] then
      true
    else if firstBypass != null then
      throw ''
        network-forwarding-model: selector-default-route-bypasses-core

        upstreamSelector: ${upstreamSelectorName}
        interface: ${firstBypass.ifName}
        route: ${builtins.toJSON firstBypass.route}
        access: ${toString bypassAccess}
        tenant: ${bypassTenantText}
        expected: default-reachability from the upstream-selector must use a selector-to-core link
      ''
    else if firstMissing != null then
      throw ''
        network-forwarding-model: selector-default-route-missing

        upstreamSelector: ${upstreamSelectorName}
        requirement: ${formatPair firstMissing}
        coreNodes: ${builtins.concatStringsSep "," coreNodeNames}
        expected: internet egress requires a default-reachability route on the selector-to-core transport link
      ''
    else
      true;
}
