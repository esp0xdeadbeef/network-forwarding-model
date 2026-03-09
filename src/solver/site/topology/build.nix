{ lib }:

let
  derive = import ../../../util/derive.nix { inherit lib; };
  p2pAlloc = import ../../../../lib/p2p/alloc.nix { inherit lib; };
  topoResolve = import ../../../../lib/topology-resolve.nix { inherit lib; };
  utils = import ../../../util { inherit lib; };

  firstOrNull = xs: if xs == [ ] then null else builtins.head xs;

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

  normalizeRoutes =
    iface:
    (builtins.removeAttrs iface [
      "routes4"
      "routes6"
    ])
    // {
      routes =
        if iface ? routes && builtins.isAttrs iface.routes then
          {
            ipv4 = iface.routes.ipv4 or [ ];
            ipv6 = iface.routes.ipv6 or [ ];
          }
        else
          {
            ipv4 = iface.routes4 or [ ];
            ipv6 = iface.routes6 or [ ];
          };
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

  tenantNameFromSegments =
    segments:
    let
      parts = lib.concatMap (
        seg:
        let
          s = toString seg;
          p = lib.splitString ":" s;
        in
        if builtins.length p == 2 then
          [
            {
              ns = builtins.elemAt p 0;
              name = builtins.elemAt p 1;
            }
          ]
        else
          [ ]
      ) segments;

      hits = lib.filter (x: (x.ns == "tenants" || x.ns == "tenant") && x.name != "") parts;
    in
    if hits == [ ] then null else (builtins.head hits).name;

  parseTenantNameFromAttachment =
    a:
    let
      kind = toString (a.kind or "");
      directName =
        if a ? tenant && a.tenant != null then
          toString a.tenant
        else if a ? tenantName && a.tenantName != null then
          toString a.tenantName
        else if a ? name && a.name != null && kind == "tenant" then
          toString a.name
        else if
          a ? subject
          && builtins.isAttrs a.subject
          && (a.subject.kind or null) == "tenant"
          && (a.subject.name or null) != null
        then
          toString a.subject.name
        else if
          a ? ingressSubject
          && builtins.isAttrs a.ingressSubject
          && (a.ingressSubject.kind or null) == "tenant"
          && (a.ingressSubject.name or null) != null
        then
          toString a.ingressSubject.name
        else if
          a ? from
          && builtins.isAttrs a.from
          && (a.from.kind or null) == "tenant"
          && (a.from.name or null) != null
        then
          toString a.from.name
        else if
          a ? to && builtins.isAttrs a.to && (a.to.kind or null) == "tenant" && (a.to.name or null) != null
        then
          toString a.to.name
        else
          null;

      segmentDerived = tenantNameFromSegments (
        lib.filter (s: s != null && s != "") [
          (a.segment or null)
          (a.path or null)
          (a.ref or null)
        ]
      );
    in
    if directName != null && directName != "" then directName else segmentDerived;

  inferTenantNamesFromUnitName =
    site: unitName:
    let
      catalog = tenantCatalog site;
      tenantNames = lib.sort (a: b: a < b) (builtins.attrNames catalog);

      lowerUnit = lib.toLower (toString unitName);

      matches = lib.filter (
        tenantName:
        let
          t = lib.toLower (toString tenantName);
        in
        lib.hasSuffix "-${t}" lowerUnit
        || lib.hasSuffix "_${t}" lowerUnit
        || lib.hasSuffix ":${t}" lowerUnit
        || lowerUnit == t
      ) tenantNames;
    in
    matches;

  attachedTenantNamesForUnit =
    site: unitName:
    let
      explicit = lib.unique (
        lib.filter (x: x != null && x != "") (
          map (
            a:
            let
              owner = utils.unitRefOfAttachment a;
            in
            if builtins.isAttrs a && owner == unitName then parseTenantNameFromAttachment a else null
          ) (utils.attachmentsOf site)
        )
      );

      inferred = inferTenantNamesFromUnitName site unitName;
    in
    if explicit != [ ] then explicit else inferred;

  tenantNetworksForUnit =
    site: unitName:
    let
      catalog = tenantCatalog site;
      names = attachedTenantNamesForUnit site unitName;
    in
    builtins.listToAttrs (
      map (name: {
        name = toString name;
        value = catalog.${name};
      }) (lib.filter (name: catalog ? "${name}") names)
    );

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
        if rolesResult.traversal ? chain && builtins.length rolesResult.traversal.chain >= 2 then
          builtins.elemAt rolesResult.traversal.chain 1
        else
          null;

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
          coreNodeNames = routed1.coreNodeNames or coreNodeNames;
          policyNodeName = routed1.policyNodeName or policyNodeName;
          upstreamSelectorNodeName = routed1.upstreamSelectorNodeName or upstreamSelectorNodeName;
          uplinkCoreNames = routed1.uplinkCoreNames or (wanResult.uplinkCores or [ ]);
          uplinkNames = routed1.uplinkNames or (wanResult.uplinkNames or [ ]);
        };
    in
    routed;
}
