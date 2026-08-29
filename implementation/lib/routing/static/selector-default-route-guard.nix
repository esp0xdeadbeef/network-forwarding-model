{
  lib,
  self ? {
    outPath = ./.;
  },
  ...
}:

let
  common = import ./guard-common.nix { inherit lib self; };
  inherit (common)
    allUpstreamSelectorNames
    defaultRoutePolicy
    helpers
    link
    linkUplinkNames
    roleOf
    routeContext
    sortedUnique
    tenantsForAccess
    upstreamSelectorFor
    ;

  isDefaultRoute =
    route:
    (route.intent.kind or null) == "default-reachability"
    || (
      (route.proto or null) == "default"
      && ((route.dst or null) == helpers.default4 || (route.dst or null) == helpers.default6)
    );

  ifaceRoutes =
    iface:
    let
      routes = iface.routes or { };
    in
    (routes.ipv4 or [ ]) ++ (routes.ipv6 or [ ]) ++ (iface.routes4 or [ ]) ++ (iface.routes6 or [ ]);

  coreNodeNamesFor =
    topo:
    let
      nodes = topo.nodes or { };
    in
    if builtins.isList (topo.coreNodeNames or null) && topo.coreNodeNames != [ ] then
      sortedUnique topo.coreNodeNames
    else
      sortedUnique (lib.filter (nodeName: roleOf nodes nodeName == "core") (builtins.attrNames nodes));

  linksForSelectorCoreUplink =
    topo: upstreamSelectorName: coreSet: uplinkName:
    let
      links = topo.links or { };
      connectsSelectorAndCore =
        linkName:
        let
          members = link.membersOf (links.${linkName} or { });
        in
        builtins.elem upstreamSelectorName members
        && builtins.any (member: coreSet.${toString member} or false) members;
      uplinkMatches =
        linkName:
        let
          names = linkUplinkNames (links.${linkName} or { });
        in
        names == [ ] || builtins.elem uplinkName names;
    in
    lib.filter (linkName: connectsSelectorAndCore linkName && uplinkMatches linkName) (
      builtins.attrNames links
    );

  selectorDefaultRoutes =
    selectorNode:
    let
      interfaces = selectorNode.interfaces or { };
    in
    lib.concatMap (
      ifName:
      map (route: {
        inherit ifName route;
      }) (lib.filter isDefaultRoute (ifaceRoutes (interfaces.${ifName} or { })))
    ) (builtins.attrNames interfaces);

  formatPair =
    pair:
    let
      tenants =
        if pair.tenants == [ ] then "<unknown-tenant>" else builtins.concatStringsSep "," pair.tenants;
    in
    "access=${pair.accessName} tenant=${tenants} uplink=${pair.uplinkName}";

in
{
  validate =
    topo:
    let
      nodes = topo.nodes or { };
      upstreamSelectorNames = allUpstreamSelectorNames topo;
      upstreamSelectorText =
        if upstreamSelectorNames == [ ] then
          "<none>"
        else
          builtins.concatStringsSep "," upstreamSelectorNames;
      coreNodeNames = coreNodeNamesFor topo;
      coreSet = lib.listToAttrs (
        map (name: {
          inherit name;
          value = true;
        }) coreNodeNames
      );
      accessNodeNames = sortedUnique (
        lib.filter (nodeName: roleOf nodes nodeName == "access") (builtins.attrNames nodes)
      );
      defaultUplinkSet = (routeContext.buildFacts topo).uplinkHasDefaultSet or { };
      overlayUplinkSet = (routeContext.buildFacts topo).overlayUplinkNameSet or { };
      egressRequirements = lib.concatMap (
        accessName:
        map
          (uplinkName: {
            inherit accessName uplinkName;
            tenants = tenantsForAccess topo accessName;
          })
          (
            lib.filter (
              uplinkName:
              builtins.hasAttr uplinkName defaultUplinkSet && !(builtins.hasAttr uplinkName overlayUplinkSet)
            ) (defaultRoutePolicy.anyTrafficDefaultUplinksForAccess topo accessName)
          )
      ) accessNodeNames;

      defaults = lib.concatMap (
        selectorName:
        map (item: item // { inherit selectorName; }) (selectorDefaultRoutes (nodes.${selectorName} or { }))
      ) upstreamSelectorNames;
      links = topo.links or { };
      connectsSelectorToCore =
        selectorName: ifName:
        let
          members = link.membersOf (links.${ifName} or { });
        in
        builtins.elem selectorName members
        && builtins.any (member: coreSet.${toString member} or false) members;

      bypasses = lib.filter (
        item:
        !(connectsSelectorToCore item.selectorName item.ifName)
        && !(
          builtins.isAttrs (item.route.multipath or null)
          && builtins.isString (item.route.multipath.authority or null)
        )
      ) defaults;
      firstBypass = if bypasses == [ ] then null else builtins.head bypasses;
      bypassAccess = if firstBypass == null then null else firstBypass.route.lane.access or null;
      bypassTenants = if bypassAccess == null then [ ] else tenantsForAccess topo (toString bypassAccess);
      bypassTenantText =
        if bypassTenants == [ ] then "<unknown-tenant>" else builtins.concatStringsSep "," bypassTenants;

      # Check if ANY upstream selector has the required default route for each requirement
      coreDefaultServedByAnySelector =
        requirement:
        let
          names = allUpstreamSelectorNames topo;
        in
        if names == [ ] then
          false
        else
          builtins.any (
            name:
            let
              selector = nodes.${name} or { };
            in
            builtins.any (
              linkName:
              builtins.any isDefaultRoute (ifaceRoutes ((selector.interfaces or { }).${linkName} or { }))
            ) (linksForSelectorCoreUplink topo name coreSet requirement.uplinkName)
          ) names;

      missing = lib.filter (
        requirement: !(coreDefaultServedByAnySelector requirement)
      ) egressRequirements;
      firstMissing = if missing == [ ] then null else builtins.head missing;
    in
    if upstreamSelectorNames == [ ] || egressRequirements == [ ] then
      true
    else if firstBypass != null then
      throw ''
        network-forwarding-model: selector-default-route-bypasses-core

        upstreamSelector: ${firstBypass.selectorName}
        interface: ${firstBypass.ifName}
        route: ${builtins.toJSON firstBypass.route}
        access: ${toString bypassAccess}
        tenant: ${bypassTenantText}
        expected: default-reachability from the upstream-selector must use a selector-to-core link
      ''
    else if firstMissing != null then
      throw ''
        network-forwarding-model: selector-default-route-missing

        upstreamSelector: ${upstreamSelectorText}
        requirement: ${formatPair firstMissing}
        coreNodes: ${builtins.concatStringsSep "," coreNodeNames}
        expected: internet egress requires a default-reachability route on the selector-to-core transport link
      ''
    else
      true;
}
