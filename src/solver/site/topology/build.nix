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
      lib.mapAttrsToList (name: v: normalizeExternalDomainEntry (v // { inherit name; })) externals
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

  normalizeTenants =
    site:
    let
      tenants0 = (site.domains or { }).tenants or [ ];
    in
    if builtins.isList tenants0 then tenants0 else builtins.attrValues tenants0;

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
      tenantNames = builtins.attrNames catalog;
      lowerUnit = lib.toLower (toString unitName);
    in
    lib.filter (t: lib.hasSuffix "-${t}" lowerUnit || lowerUnit == t) tenantNames;

  tenantNetworksForUnit =
    site: unitName:
    let
      catalog = tenantCatalog site;
      names = inferTenantNamesFromUnitName site unitName;
    in
    builtins.listToAttrs (
      map (n: {
        name = n;
        value = catalog.${n};
      }) (lib.filter (n: catalog ? "${n}") names)
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
      sites ? { },
    }:
    let
      siteName = toString (site.siteName or "${enterprise}.${siteId}");

      unitNames = lib.unique (
        (builtins.attrNames (site.units or { })) ++ (builtins.attrNames (site.nodes or { }))
      );

      nodes = lib.listToAttrs (
        map (u: {
          name = toString u;
          value =
            let
              unitName = toString u;
              base = nodeFromSite site unitName;
              attachedNetworks = tenantNetworksForUnit site unitName;

              loopback = if base ? loopback then normalizeLoopback base.loopback else null;
            in
            base
            // {
              role = rolesResult.roleFromInput unitName;
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
          links = ordering;
          inherit nodes;
        };
      };

      routed0 = topoResolve (
        enforcementResult
        // {
          inherit
            siteName
            enterprise
            siteId
            nodes
            ;
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

    in
    routed1;
}
