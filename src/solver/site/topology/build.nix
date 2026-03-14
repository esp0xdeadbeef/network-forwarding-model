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
              attachedNetworks = tenantNetworksForUnit site unitName;

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
          domains = site.domains or { };
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

      finalUpstreamSelectorNodeName =
        if routed1 ? upstreamSelectorNodeName && routed1.upstreamSelectorNodeName != null then
          routed1.upstreamSelectorNodeName
        else if upstreamSelectorNodeName != null then
          upstreamSelectorNodeName
        else
          firstNodeNameByRole (routed1.nodes or { }) "upstream-selector";

      finalCoreNodeNames =
        if routed1 ? coreNodeNames && routed1.coreNodeNames != [ ] then
          routed1.coreNodeNames
        else
          coreNodeNames;

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
          upstreamSelectorNodeName = finalUpstreamSelectorNodeName;
          uplinkCoreNames = routed1.uplinkCoreNames or (wanResult.uplinkCores or [ ]);
          uplinkNames = routed1.uplinkNames or (wanResult.uplinkNames or [ ]);
        };
    in
    routed;
}
