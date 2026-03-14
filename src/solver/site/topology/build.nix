{ lib }:

let
  derive = import ../../../util/derive.nix { inherit lib; };
  p2pAlloc = import ../../../../lib/p2p/alloc.nix { inherit lib; };
  topoResolve = import ../../../../lib/topology-resolve.nix { inherit lib; };
  utils = import ../../../util { inherit lib; };

  ensureMask =
    addr: family:
    if addr == null then
      null
    else if lib.hasInfix "/" (toString addr) then
      addr
    else if family == 4 then
      "${toString addr}/32"
    else
      "${toString addr}/128";

  normalizeLoopback =
    lb:
    if !(builtins.isAttrs lb) then
      null
    else
      {
        ipv4 = ensureMask (lb.ipv4 or null) 4;
        ipv6 = ensureMask (lb.ipv6 or null) 6;
      };

  normalizeRouteList =
    routes:
    map (
      r:
      if builtins.isString r then
        { dst = r; }
      else if builtins.isAttrs r then
        r
      else
        { dst = toString r; }
    ) routes;

  normalizeRoutes =
    iface:
    let
      base =
        (builtins.removeAttrs iface [
          "routes4"
          "routes6"
        ])
        // {
          routes =
            if iface ? routes && builtins.isAttrs iface.routes then
              {
                ipv4 = normalizeRouteList (iface.routes.ipv4 or [ ]);
                ipv6 = normalizeRouteList (iface.routes.ipv6 or [ ]);
              }
            else
              {
                ipv4 = normalizeRouteList (iface.routes4 or [ ]);
                ipv6 = normalizeRouteList (iface.routes6 or [ ]);
              };
        };
    in
    base
    // {
      uplinkRoutes4 = normalizeRouteList (iface.uplinkRoutes4 or [ ]);
      uplinkRoutes6 = normalizeRouteList (iface.uplinkRoutes6 or [ ]);
    };

  nodeFromSite =
    site: n:
    if site ? units && builtins.isAttrs site.units && site.units ? "${n}" then
      site.units.${n}
    else if site ? nodes && builtins.isAttrs site.nodes && site.nodes ? "${n}" then
      site.nodes.${n}
    else
      { };

  normalizeExternalDomainEntry =
    x:
    if builtins.isString x then
      {
        name = toString x;
        kind = "external";
      }
    else if builtins.isAttrs x && (x.name or null) != null then
      x
      // {
        name = toString x.name;
        kind = x.kind or "external";
      }
    else
      null;

  externalDomainNameOf =
    x:
    if builtins.isString x then
      toString x
    else if builtins.isAttrs x && (x.name or null) != null then
      toString x.name
    else
      null;

  externalDomainsListFrom =
    externals:
    if builtins.isList externals then
      lib.filter (x: x != null) (map normalizeExternalDomainEntry externals)
    else if builtins.isAttrs externals then
      lib.mapAttrsToList (
        name: v:
        let
          normalized = normalizeExternalDomainEntry (v // { inherit name; });
        in
        if normalized == null then
          {
            name = toString name;
            kind = "external";
          }
        else
          normalized
      ) externals
    else
      [ ];

  externalRefNamesFromContract =
    x:
    if builtins.isList x then
      lib.unique (lib.concatMap externalRefNamesFromContract x)
    else if builtins.isAttrs x then
      let
        self =
          if (x.kind or null) == "external" && (x.name or null) != null then [ (toString x.name) ] else [ ];
      in
      lib.unique (self ++ lib.concatMap externalRefNamesFromContract (builtins.attrValues x))
    else
      [ ];

  overlayNamesFromTransport =
    transport:
    if !(builtins.isAttrs transport) then
      [ ]
    else
      let
        overlays = transport.overlays or [ ];
      in
      if builtins.isList overlays then
        lib.unique (
          lib.concatMap (
            overlay:
            if builtins.isString overlay then
              [ (toString overlay) ]
            else if builtins.isAttrs overlay && (overlay.name or null) != null then
              [ (toString overlay.name) ]
            else
              [ ]
          ) overlays
        )
      else if builtins.isAttrs overlays then
        lib.sort (a: b: a < b) (builtins.attrNames overlays)
      else
        [ ];

  mergeExternalDomains =
    existing: names:
    let
      existingList = externalDomainsListFrom existing;
      existingByName = builtins.listToAttrs (
        map (entry: {
          name = entry.name;
          value = entry;
        }) existingList
      );

      addedByName = builtins.listToAttrs (
        map (name: {
          name = toString name;
          value = {
            name = toString name;
            kind = "external";
          };
        }) (lib.filter (name: name != null && name != "") names)
      );
    in
    builtins.attrValues (existingByName // addedByName);

  materializeSiteDomains =
    site:
    let
      domains0 = site.domains or { };
      requiredExternalNames = lib.unique (
        (overlayNamesFromTransport (site.transport or { }))
        ++ (externalRefNamesFromContract (site.communicationContract or { }))
      );
      externals0 = domains0.externals or [ ];
      externals1 = mergeExternalDomains externals0 requiredExternalNames;
    in
    domains0
    // {
      externals = externals1;
    };

  tenantCatalog =
    site:
    let
      tenants = (site.domains or { }).tenants or [ ];
    in
    builtins.listToAttrs (
      map (t: {
        name = toString t.name;
        value = {
          kind = t.kind or "tenant";
          name = toString t.name;
          ipv4 = t.ipv4 or null;
          ipv6 = t.ipv6 or null;
        };
      }) (lib.filter (t: builtins.isAttrs t && (t.name or null) != null) tenants)
    );

  inferTenantNamesFromUnitName =
    site: unitName:
    let
      catalog = tenantCatalog site;
      tenantNames = lib.sort (a: b: a < b) (builtins.attrNames catalog);
      lowerUnit = lib.toLower (toString unitName);
    in
    lib.filter (
      tenantName:
      let
        t = lib.toLower (toString tenantName);
      in
      lib.hasSuffix "-${t}" lowerUnit
      || lib.hasSuffix "_${t}" lowerUnit
      || lib.hasSuffix ":${t}" lowerUnit
      || lowerUnit == t
    ) tenantNames;

  tenantNetworksForUnit =
    site: unitName:
    let
      catalog = tenantCatalog site;
      names = inferTenantNamesFromUnitName site unitName;
    in
    builtins.listToAttrs (
      map (name: {
        name = toString name;
        value = catalog.${name};
      }) (lib.filter (name: catalog ? "${name}") names)
    );

  firstNodeNameByRole =
    nodes: role:
    let
      names = lib.sort (a: b: a < b) (
        builtins.attrNames (lib.filterAttrs (_: n: (n.role or null) == role) nodes)
      );
    in
    if names == [ ] then null else builtins.head names;

  firstExistingName =
    nodes: names:
    let
      present = lib.filter (name: nodes ? "${name}") names;
    in
    if present == [ ] then null else builtins.head present;

in
{
  build =
    {
      lib,
      site,
      siteId,
      enterprise,
      ordering,
      p2pPool,
      rolesResult,
      wanResult,
      enforcementResult,
    }:
    let
      siteName = toString (site.siteName or "${enterprise}.${siteId}");

      siteDomains = materializeSiteDomains site;
      siteForTopology = site // {
        domains = siteDomains;
      };

      unitNames = lib.unique (
        (if site ? units && builtins.isAttrs site.units then builtins.attrNames site.units else [ ])
        ++ (if site ? nodes && builtins.isAttrs site.nodes then builtins.attrNames site.nodes else [ ])
        ++ (rolesResult.traversal.chain or [ ])
        ++ builtins.attrNames (rolesResult.traversal.inferred or { })
      );

      nodes = lib.listToAttrs (
        map (u: {
          name = toString u;
          value =
            let
              unitName = toString u;
              base = nodeFromSite site unitName;
              attachedNetworks = tenantNetworksForUnit siteForTopology unitName;

              loopback =
                if base ? loopback then
                  normalizeLoopback base.loopback
                else if site ? routerLoopbacks && site.routerLoopbacks ? "${unitName}" then
                  normalizeLoopback site.routerLoopbacks.${unitName}
                else
                  null;
            in
            base
            // {
              role = rolesResult.roleFromInput unitName;
              containers = base.containers or [ "default" ];
            }
            // lib.optionalAttrs (attachedNetworks != { }) {
              networks = attachedNetworks;
            }
            // lib.optionalAttrs (loopback != null) {
              inherit loopback;
            };
        }) unitNames
      );

      p2pLinks = p2pAlloc.alloc {
        site = {
          p2p-pool = p2pPool;
          links = lib.filter (p: builtins.isList p && builtins.length p == 2) ordering;
          inherit nodes;
          domains = siteDomains;
        };
      };

      coreNodeNames = lib.sort (a: b: a < b) (
        map toString (lib.filter (u: rolesResult.roleFromInput u == "core") unitNames)
      );

      policyNodeName = if rolesResult.policyUnit == null then null else toString rolesResult.policyUnit;

      upstreamSelectorNodeName =
        let
          selectorNames = lib.sort (a: b: a < b) (
            map toString (lib.filter (u: rolesResult.roleFromInput u == "upstream-selector") unitNames)
          );
        in
        if selectorNames == [ ] then null else builtins.head selectorNames;

      routed0 = topoResolve (
        enforcementResult
        // siteForTopology
        // {
          inherit
            siteName
            enterprise
            siteId
            coreNodeNames
            policyNodeName
            upstreamSelectorNodeName
            ;
          uplinkCoreNames = wanResult.uplinkCores or [ ];
          uplinkNames = wanResult.uplinkNames or [ ];
          p2p-pool = p2pPool;
          inherit nodes;
          links = p2pLinks // (wanResult.wanLinks or { }) // (site.links or { });
        }
      );

      routed1 = routed0 // {
        nodes = lib.mapAttrs (
          _: node:
          node
          // {
            interfaces = lib.mapAttrs (_: normalizeRoutes) (node.interfaces or { });
          }
        ) (routed0.nodes or { });
      };

      finalPolicyNodeName =
        if routed1 ? policyNodeName && routed1.policyNodeName != null then
          routed1.policyNodeName
        else if policyNodeName != null then
          policyNodeName
        else
          firstNodeNameByRole (routed1.nodes or { }) "policy";

      finalCoreNodeNames =
        if routed1 ? coreNodeNames && routed1.coreNodeNames != [ ] then
          routed1.coreNodeNames
        else
          coreNodeNames;

      multiWan = builtins.length (wanResult.uplinkCores or [ ]) > 1;

      fallbackCoreNodeName =
        let
          nodes1 = routed1.nodes or { };
          fromFinalCores = firstExistingName nodes1 finalCoreNodeNames;
        in
        if fromFinalCores != null then fromFinalCores else firstNodeNameByRole nodes1 "core";

      selectedUpstreamSelectorNodeName =
        let
          nodes1 = routed1.nodes or { };

          explicitSelector =
            if routed1 ? upstreamSelectorNodeName && routed1.upstreamSelectorNodeName != null then
              routed1.upstreamSelectorNodeName
            else if upstreamSelectorNodeName != null then
              upstreamSelectorNodeName
            else
              firstNodeNameByRole nodes1 "upstream-selector";
        in
        if multiWan then
          if explicitSelector != null && nodes1 ? "${explicitSelector}" then
            explicitSelector
          else
            fallbackCoreNodeName
        else
          fallbackCoreNodeName;

      _assertUpstreamSelectorNodeName =
        if
          selectedUpstreamSelectorNodeName != null
          && (routed1.nodes or { } ? "${selectedUpstreamSelectorNodeName}")
        then
          true
        else
          throw ''
            network-solver: failed to determine valid upstreamSelectorNodeName

            site: ${enterprise}.${siteId}
            multiWan: ${if multiWan then "true" else "false"}
            candidate: ${toString selectedUpstreamSelectorNodeName}
            nodes: ${builtins.toJSON (builtins.attrNames (routed1.nodes or { }))}
          '';

      routed =
        builtins.removeAttrs routed1 [
          "_enforcement"
          "_nat"
          "_loopbackResolution"
          "compilerIR"
          "p2p-pool"
          "tenantV4Base"
          "ulaPrefix"
          "routerLoopbacks"
        ]
        // {
          inherit enterprise siteId;
          siteName = routed1.siteName or siteName;
          coreNodeNames = finalCoreNodeNames;
          policyNodeName = finalPolicyNodeName;
          upstreamSelectorNodeName = builtins.seq _assertUpstreamSelectorNodeName selectedUpstreamSelectorNodeName;
          uplinkCoreNames = routed1.uplinkCoreNames or (wanResult.uplinkCores or [ ]);
          uplinkNames = routed1.uplinkNames or (wanResult.uplinkNames or [ ]);
        };
    in
    routed;
}
