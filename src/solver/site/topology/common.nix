{ lib }:

let
  routes = import ../../../../lib/model/routes.nix { inherit lib; };
  ip = import ../../../../lib/net/ip-utils.nix { inherit lib; };

  dedupeRoutes = routes.dedupeRoutes;
  stripMask = ip.stripMask;

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

  normalizeRouteEntry =
    r:
    if builtins.isString r then
      { dst = r; }
    else if builtins.isAttrs r then
      builtins.removeAttrs r [ "preserveDst" ]
    else
      { dst = toString r; };

  normalizeRouteList = routes0: dedupeRoutes (map normalizeRouteEntry routes0);

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
    if
      site ? topology
      && builtins.isAttrs site.topology
      && site.topology ? nodes
      && builtins.isAttrs site.topology.nodes
      && site.topology.nodes ? "${n}"
    then
      site.topology.nodes.${n}
    else if site ? units && builtins.isAttrs site.units && site.units ? "${n}" then
      site.units.${n}
    else if site ? nodes && builtins.isAttrs site.nodes && site.nodes ? "${n}" then
      site.nodes.${n}
    else if
      site ? forwardingSemantics
      && builtins.isAttrs site.forwardingSemantics
      && site.forwardingSemantics ? nodes
      && builtins.isAttrs site.forwardingSemantics.nodes
      && site.forwardingSemantics.nodes ? "${n}"
    then
      site.forwardingSemantics.nodes.${n}
    else
      { };

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
  inherit
    stripMask
    ensureMask
    normalizeLoopback
    normalizeRouteEntry
    normalizeRouteList
    normalizeRoutes
    nodeFromSite
    firstNodeNameByRole
    ;
}
