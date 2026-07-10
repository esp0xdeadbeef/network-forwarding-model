{ lib, self ? { outPath = ./.; }, ... }:

let
  link = import (self.outPath + "/implementation/lib/topology/link-utils.nix") { inherit lib self; };
  defaultRoutePolicy = import (self.outPath + "/implementation/lib/routing/default-route-policy.nix") { inherit lib; };
  helpers = import (self.outPath + "/implementation/lib/routing/static-helpers.nix") { inherit lib self; };
  routeContext = import (self.outPath + "/implementation/lib/routing/route-context.nix") { inherit lib self; };

  sortedUnique = xs: lib.sort (a: b: toString a < toString b) (lib.unique (map toString xs));
  roleOf = nodes: nodeName: (nodes.${nodeName} or { }).role or null;
  ifaceRoutes = iface: let routes = iface.routes or { }; in (routes.ipv4 or [ ]) ++ (iface.routes4 or [ ]);
  routeMatches = prefix: route: (route.dst or null) == prefix && (route.intent.kind or null) == "internal-reachability";

  upstreamSelectorFor =
    topo:
    let
      nodes = topo.nodes or { };
      explicit = topo.upstreamSelectorNodeName or null;
      inferred = lib.filter (nodeName: roleOf nodes nodeName == "upstream-selector") (builtins.attrNames nodes);
    in
    if explicit != null then toString explicit else if inferred == [ ] then null else builtins.head (sortedUnique inferred);

  # All upstream-selector node names (for combined fabrics with multiple upstream paths)
  allUpstreamSelectorNames =
    topo:
    let
      nodes = topo.nodes or { };
    in
    sortedUnique (lib.filter (nodeName: roleOf nodes nodeName == "upstream-selector") (builtins.attrNames nodes));

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

  tenantIpv4ByName =
    topo:
    builtins.listToAttrs (
      lib.concatMap
        (
          tenant:
          if builtins.isAttrs tenant && (tenant.name or null) != null && (tenant.ipv4 or null) != null then
            [ { name = toString tenant.name; value = helpers.canonicalCidr tenant.ipv4; } ]
          else
            [ ]
        )
        ((topo.domains or { }).tenants or [ ])
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

  coreSelectorLinks =
    topo: upstreamSelectorName: coreName: uplinkName:
    let
      links = topo.links or { };
      matches =
        linkName:
        let
          members = link.membersOf (links.${linkName} or { });
          uplinks = linkUplinkNames (links.${linkName} or { });
        in
        builtins.elem upstreamSelectorName members
        && builtins.elem coreName members
        && (uplinks == [ ] || builtins.elem uplinkName uplinks);
    in
    lib.filter matches (builtins.attrNames links);

  coreNamesForUplink =
    topo: routeFacts: uplinkName:
    let
      nodes = topo.nodes or { };
      fromFacts = (routeFacts.uplinkCoreNamesByUplink or { }).${uplinkName} or [ ];
      fromNodeUplinks = lib.filter (
        nodeName: roleOf nodes nodeName == "core" && builtins.hasAttr uplinkName ((nodes.${nodeName} or { }).uplinks or { })
      ) (builtins.attrNames nodes);
    in
    sortedUnique (fromFacts ++ fromNodeUplinks);

  formatRequirement =
    r:
    "tenant=${r.tenantName} prefix=${r.prefix} access=${r.accessName} uplink=${r.uplinkName} core=${r.coreName}";

in
{
  validate =
    topo:
    let
      nodes = topo.nodes or { };
      upstreamSelectorName = upstreamSelectorFor topo;
      routeFacts = routeContext.buildFacts topo;
      defaultUplinkSet = routeFacts.uplinkHasDefaultSet or { };
      overlayUplinkSet = routeFacts.overlayUplinkNameSet or { };
      tenantPrefixes = tenantIpv4ByName topo;
      accessNodeNames = sortedUnique (
        lib.filter (nodeName: roleOf nodes nodeName == "access") (builtins.attrNames nodes)
      );
      defaultUplinksForAccess =
        accessName:
        lib.filter
          (uplinkName: builtins.hasAttr uplinkName defaultUplinkSet && !(builtins.hasAttr uplinkName overlayUplinkSet))
          (defaultRoutePolicy.anyTrafficDefaultUplinksForAccess topo accessName);
      requirements =
        lib.concatMap
          (
            accessName:
            lib.concatMap
              (
                tenantName:
                lib.concatMap
                  (
                    uplinkName:
                    map
                      (coreName: {
                        inherit accessName coreName tenantName uplinkName;
                        prefix = tenantPrefixes.${tenantName};
                      })
                      (coreNamesForUplink topo routeFacts uplinkName)
                  )
                  (defaultUplinksForAccess accessName)
              )
              (lib.filter (tenantName: builtins.hasAttr tenantName tenantPrefixes) (tenantsForAccess topo accessName))
          )
          accessNodeNames;

      routesOn =
        coreName: ifName:
        ifaceRoutes (((nodes.${coreName} or { }).interfaces or { }).${ifName} or { });

      # Find the upstream-selector that connects to the given core
      upstreamSelectorForCore =
        coreName:
        let
          names = allUpstreamSelectorNames topo;
          connectsToCore = name:
            builtins.any
              (linkName:
                let members = link.membersOf (topo.links.${linkName} or { });
                in builtins.elem name members && builtins.elem coreName members
              )
              (builtins.attrNames (topo.links or { }));
        in
        lib.findSingle connectsToCore null null names;

      expectedLinksFor = r:
        let
          selector = upstreamSelectorForCore r.coreName;
        in
        if selector == null then [ ]
        else coreSelectorLinks topo selector r.coreName r.uplinkName;
      expectedRouteExists =
        r:
        builtins.any (ifName: builtins.any (routeMatches r.prefix) (routesOn r.coreName ifName)) (expectedLinksFor r);
      wrongRoutes =
        r:
        let expected = lib.listToAttrs (map (name: { inherit name; value = true; }) (expectedLinksFor r));
        in
        lib.concatMap
          (
            ifName:
            map
              (route: { inherit ifName route; requirement = r; })
              (lib.filter (routeMatches r.prefix) (routesOn r.coreName ifName))
          )
          (lib.filter (ifName: !(expected.${ifName} or false)) (builtins.attrNames (((nodes.${r.coreName} or { }).interfaces or { }))));

      wrong = lib.concatMap wrongRoutes requirements;
      firstWrong = if wrong == [ ] then null else builtins.head wrong;
      missing = lib.filter (r: !(expectedRouteExists r)) requirements;
      firstMissing = if missing == [ ] then null else builtins.head missing;
    in
    if upstreamSelectorName == null || requirements == [ ] then
      true
    else if firstWrong != null then
      throw ''
        network-forwarding-model: core-return-route-wrong-interface

        requirement: ${formatRequirement firstWrong.requirement}
        interface: ${firstWrong.ifName}
        route: ${builtins.toJSON firstWrong.route}
        expected: tenant return route must use the core-to-upstream-selector transport link
      ''
    else if firstMissing != null then
      throw ''
        network-forwarding-model: core-return-route-missing

        requirement: ${formatRequirement firstMissing}
        expectedLinks: ${builtins.concatStringsSep "," (expectedLinksFor firstMissing)}
        expected: internet egress requires a core return route to the tenant prefix via the upstream-selector
      ''
    else
      true;
}
