{ lib }:

let
  derive = import ../../../util/derive.nix { inherit lib; };
  p2pAlloc = import ../../../../lib/p2p/alloc.nix { inherit lib; };
  topoResolve = import ../../../../lib/topology-resolve.nix { inherit lib; };
  routes = import ../../../../lib/model/routes.nix { inherit lib; };
  utils = import ../../../util { inherit lib; };

  dedupeRoutes = routes.dedupeRoutes;

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
    routes0:
    dedupeRoutes (
      map (
        r:
        if builtins.isString r then
          { dst = r; }
        else if builtins.isAttrs r then
          r
        else
          { dst = toString r; }
      ) routes0
    );

  stripRendererUnsafe =
    iface:
    builtins.removeAttrs iface [
      "acceptRA"
      "dhcp"
      "ra6Prefixes"
      "addr6Public"
    ];

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
    stripRendererUnsafe (
      base
      // {
        uplinkRoutes4 = normalizeRouteList (iface.uplinkRoutes4 or [ ]);
        uplinkRoutes6 = normalizeRouteList (iface.uplinkRoutes6 or [ ]);
      }
    );

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

  normalizeTenants =
    site:
    let
      tenants0 = (site.domains or { }).tenants or [ ];
      tenants1 =
        if builtins.isList tenants0 then
          tenants0
        else if builtins.isAttrs tenants0 then
          builtins.attrValues (
            lib.mapAttrs (
              name: v:
              if builtins.isAttrs v then
                v // { name = toString (v.name or name); }
              else
                {
                  name = toString name;
                }
            ) tenants0
          )
        else
          [ ];
    in
    lib.filter (t: builtins.isAttrs t && (t.name or null) != null) tenants1;

  tenantCatalog =
    site:
    builtins.listToAttrs (
      map (t: {
        name = toString t.name;
        value = {
          kind = t.kind or "tenant";
          name = toString t.name;
          ipv4 = t.ipv4 or null;
          ipv6 = t.ipv6 or null;
        };
      }) (normalizeTenants site)
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

  tenantPrefixesOfSite =
    site:
    let
      tenants = normalizeTenants site;

      ipv4 = lib.unique (
        lib.filter (x: x != null) (
          map (t: if (t.ipv4 or null) != null then toString t.ipv4 else null) tenants
        )
      );

      ipv6 = lib.unique (
        lib.filter (x: x != null) (
          map (t: if (t.ipv6 or null) != null then toString t.ipv6 else null) tenants
        )
      );
    in
    {
      inherit ipv4 ipv6;
    };

  firstNodeNameByRole =
    nodes: role:
    let
      names = lib.sort (a: b: a < b) (
        builtins.attrNames (lib.filterAttrs (_: n: (n.role or null) == role) nodes)
      );
    in
    if names == [ ] then null else builtins.head names;

  normalizeOverlay =
    x:
    if builtins.isString x then
      {
        name = toString x;
      }
    else if builtins.isAttrs x && (x.name or null) != null then
      x // { name = toString x.name; }
    else
      null;

  overlayItemsFrom =
    site:
    let
      overlays0 = ((site.transport or { }).overlays or [ ]);
    in
    if builtins.isList overlays0 then
      lib.filter (x: x != null) (map normalizeOverlay overlays0)
    else if builtins.isAttrs overlays0 then
      lib.filter (x: x != null) (
        lib.mapAttrsToList (name: v: normalizeOverlay (v // { inherit name; })) overlays0
      )
    else
      [ ];

  overlayTargetNamesFrom =
    x:
    if x == null then
      [ ]
    else if builtins.isString x then
      [ (toString x) ]
    else if builtins.isList x then
      lib.concatMap overlayTargetNamesFrom x
    else if builtins.isAttrs x then
      let
        direct = lib.filter (v: v != null) [
          (if (x.unit or null) != null then toString x.unit else null)
          (if (x.node or null) != null then toString x.node else null)
        ];
      in
      if direct != [ ] then
        direct
      else
        lib.concatMap overlayTargetNamesFrom (
          lib.filter (v: v != null) [
            (x.terminateOn or null)
            (x.terminatesOn or null)
            (x.terminatedOn or null)
          ]
        )
    else
      [ ];

  overlayPeerSiteRefOf =
    enterprise: overlay:
    let
      raw =
        overlay.peerSite or overlay.peerSiteId or overlay.remoteSite or overlay.site or overlay.peer
          or null;
      s =
        if raw == null then
          null
        else if builtins.isString raw then
          toString raw
        else if builtins.isAttrs raw && (raw.site or null) != null then
          toString raw.site
        else if builtins.isAttrs raw && (raw.siteId or null) != null then
          toString raw.siteId
        else if builtins.isAttrs raw && (raw.name or null) != null then
          toString raw.name
        else
          null;
    in
    if s == null then
      null
    else if lib.hasInfix "." s then
      s
    else
      "${enterprise}.${s}";

  siteByRef =
    allSites: ref:
    let
      parts = lib.splitString "." (toString ref);
    in
    if builtins.length parts != 2 then
      null
    else
      let
        ent = builtins.elemAt parts 0;
        sid = builtins.elemAt parts 1;
      in
      if allSites ? "${ent}" && builtins.isAttrs allSites.${ent} && allSites.${ent} ? "${sid}" then
        allSites.${ent}.${sid}
      else
        null;

  overlayReachabilityForSite =
    {
      enterprise,
      site,
      allSites,
    }:
    builtins.listToAttrs (
      map (
        overlay:
        let
          overlayName = toString overlay.name;
          peerSiteRef = overlayPeerSiteRefOf enterprise overlay;
          peerSite0 = if peerSiteRef == null then null else siteByRef allSites peerSiteRef;
          peerSite =
            if peerSite0 == null then null else peerSite0 // { domains = materializeSiteDomains peerSite0; };
          peerPrefixes =
            if peerSite == null then
              {
                ipv4 = [ ];
                ipv6 = [ ];
              }
            else
              tenantPrefixesOfSite peerSite;
          terminateOn = lib.unique (overlayTargetNamesFrom overlay);

          routes4 = map (dst: {
            inherit dst;
            proto = "overlay";
            overlay = overlayName;
            peerSite = peerSiteRef;
          }) peerPrefixes.ipv4;

          routes6 = map (dst: {
            inherit dst;
            proto = "overlay";
            overlay = overlayName;
            peerSite = peerSiteRef;
          }) peerPrefixes.ipv6;
        in
        {
          name = overlayName;
          value = {
            overlay = overlayName;
            peerSite = peerSiteRef;
            terminateOn = terminateOn;
            routes4 = routes4;
            routes6 = routes6;
          };
        }
      ) (overlayItemsFrom site)
    );

  transitAdjacenciesFromLinks =
    links:
    let
      linkNames = lib.sort (a: b: a < b) (builtins.attrNames links);
      p2pLinkNames = lib.filter (linkName: (links.${linkName}.kind or null) == "p2p") linkNames;

      mkEndpoint = nodeName: ep: {
        node = nodeName;
        interface = ep.interface or null;
        addr4 = ep.addr4 or null;
        addr6 = ep.addr6 or null;
      };

      mkAdjacency =
        linkName:
        let
          link = links.${linkName};
          endpoints = link.endpoints or { };
          nodeNames = lib.sort (a: b: a < b) (builtins.attrNames endpoints);
        in
        {
          name = linkName;
          kind = "p2p";
          link = linkName;
          members = nodeNames;
          endpoints = builtins.listToAttrs (
            map (nodeName: {
              name = nodeName;
              value = mkEndpoint nodeName endpoints.${nodeName};
            }) nodeNames
          );
        };
    in
    map mkAdjacency p2pLinkNames;

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
      sites ? { },
    }:
    let
      siteName = toString (site.siteName or "${enterprise}.${siteId}");

      siteDomains = materializeSiteDomains site;

      overlayReachability = overlayReachabilityForSite {
        inherit enterprise;
        site = site // {
          domains = siteDomains;
        };
        allSites = sites;
      };

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
        siteForTopology
        // enforcementResult
        // {
          inherit
            siteName
            enterprise
            siteId
            coreNodeNames
            policyNodeName
            upstreamSelectorNodeName
            overlayReachability
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

      emittedUpstreamSelectorNodeName =
        let
          nodes1 = routed1.nodes or { };

          candidate =
            if routed1 ? upstreamSelectorNodeName && routed1.upstreamSelectorNodeName != null then
              routed1.upstreamSelectorNodeName
            else if upstreamSelectorNodeName != null then
              upstreamSelectorNodeName
            else
              firstNodeNameByRole nodes1 "upstream-selector";
        in
        if
          candidate != null
          && nodes1 ? "${candidate}"
          && (nodes1.${candidate}.role or null) == "upstream-selector"
        then
          candidate
        else
          null;

      _assertUpstreamSelectorNodeName =
        if emittedUpstreamSelectorNodeName == null then
          true
        else if
          (routed1.nodes or { } ? "${emittedUpstreamSelectorNodeName}")
          && ((routed1.nodes.${emittedUpstreamSelectorNodeName}.role or null) == "upstream-selector")
        then
          true
        else
          throw ''
            network-solver: invalid emitted upstreamSelectorNodeName

            site: ${enterprise}.${siteId}
            candidate: ${toString emittedUpstreamSelectorNodeName}
            nodes: ${builtins.toJSON (builtins.attrNames (routed1.nodes or { }))}
          '';

      realizedTransitAdjacencies = transitAdjacenciesFromLinks (routed1.links or { });

      existingTopology =
        if routed1 ? topology && builtins.isAttrs routed1.topology then routed1.topology else { };

      existingTransit =
        if routed1 ? transit && builtins.isAttrs routed1.transit then routed1.transit else { };

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
          inherit enterprise siteId overlayReachability;
          siteName = routed1.siteName or siteName;
          coreNodeNames = finalCoreNodeNames;
          policyNodeName = finalPolicyNodeName;
          upstreamSelectorNodeName = builtins.seq _assertUpstreamSelectorNodeName emittedUpstreamSelectorNodeName;
          uplinkCoreNames = routed1.uplinkCoreNames or (wanResult.uplinkCores or [ ]);
          uplinkNames = routed1.uplinkNames or (wanResult.uplinkNames or [ ]);
          topology = existingTopology // {
            nodes = routed1.nodes or { };
          };
          transit = existingTransit // {
            ordering = existingTransit.ordering or ordering;
            adjacencies = realizedTransitAdjacencies;
          };
        };
    in
    routed;
}
