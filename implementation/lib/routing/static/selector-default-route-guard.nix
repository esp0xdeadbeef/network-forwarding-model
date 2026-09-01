{
  lib,
  self ? {
    outPath = ./.;
  },
  ...
}:

let
  common = import ./guard-common.nix { inherit lib self; };
  facts = import ./selector-default-route-facts.nix { inherit lib self; };
  inherit (common)
    allUpstreamSelectorNames
    defaultRoutePolicy
    link
    roleOf
    routeContext
    sortedUnique
    tenantsForAccess
    ;
  inherit (facts)
    coreNodeNamesFor
    formatPair
    ifaceRoutes
    isDefaultRoute
    linksForSelectorCoreUplink
    selectorDefaultRoutes
    ;
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

      # Check if ANY upstream selector has the required default route for each
      # requirement. FS-315 allows a single multipath default (an explicit
      # member set) to serve all of the requirement's uplinks instead of one
      # direct route per selector-to-core link.
      multipathServes =
        route: requirement:
        let
          lane = route.lane or { };
          uplinks = lane.uplinks or [ ];
          access = lane.access or null;
        in
        builtins.isAttrs (route.multipath or null)
        && builtins.isString (route.multipath.authority or null)
        && (access == null || access == requirement.accessName)
        && (uplinks == [ ] || builtins.elem requirement.uplinkName uplinks);

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
              interfaces = selector.interfaces or { };
              direct = builtins.any (
                linkName: builtins.any isDefaultRoute (ifaceRoutes (interfaces.${linkName} or { }))
              ) (linksForSelectorCoreUplink topo name coreSet requirement.uplinkName);
              multipath = builtins.any (
                ifaceName:
                builtins.any (route: multipathServes route requirement) (
                  ifaceRoutes (interfaces.${ifaceName} or { })
                )
              ) (builtins.attrNames interfaces);
            in
            direct || multipath
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
