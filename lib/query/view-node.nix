{ lib }:

nodeName: topo:

let
  sanitize = import ./sanitize.nix { inherit lib; };
  routes = import ../model/routes.nix { inherit lib; };

  ifaceRoutes = routes.ifaceRoutes;

  nodes = topo.nodes or { };

  fabricHost =
    if topo ? coreNodeNames && builtins.isList topo.coreNodeNames && topo.coreNodeNames != [ ] then
      builtins.elemAt topo.coreNodeNames 0
    else
      throw "view-node: missing required topo.coreNodeNames (fabric host)";

  corePrefix = "${fabricHost}-";
  isCoreContext = lib.hasPrefix corePrefix nodeName;

  parts = lib.splitString "-" nodeName;
  lastPart = if parts == [ ] then "" else lib.last parts;

  haveVidSuffix = isCoreContext && (builtins.match "^[0-9]+$" lastPart != null);

  vid = if haveVidSuffix then lib.toInt lastPart else null;

  keepRoute4 =
    r:
    if vid == null then
      true
    else
      let
        tenantPrefix = if topo ? tenantV4Base then "${topo.tenantV4Base}.${toString vid}.0/24" else null;
      in
      tenantPrefix == null || (r.dst or "") == tenantPrefix;

  keepRoute6 =
    r:
    if vid == null then
      true
    else
      let
        tenantPrefix = if topo ? ulaPrefix then "${topo.ulaPrefix}:${toString vid}::/64" else null;
      in
      tenantPrefix == null || (r.dst or "") == tenantPrefix;

  sanitizeTenantRoutes =
    iface:
    if vid == null then
      iface
    else
      let
        rs = ifaceRoutes iface;
      in
      iface
      // {
        routes = {
          ipv4 = builtins.filter keepRoute4 rs.ipv4;
          ipv6 = builtins.filter keepRoute6 rs.ipv6;
        };
      };

  rewriteVlanId =
    iface:
    if vid != null && (iface.kind or null) == "p2p" && (iface.vlanId or null) != null then
      iface // { vlanId = iface.vlanId + vid; }
    else
      iface;

  ifaces0 =
    if nodes ? "${nodeName}" && (nodes.${nodeName} ? interfaces) then
      nodes.${nodeName}.interfaces
    else
      { };

  interfaces = lib.mapAttrs (_: iface: sanitizeTenantRoutes (rewriteVlanId iface)) ifaces0;

in
sanitize {
  node = nodeName;
  interfaces = interfaces;
}
