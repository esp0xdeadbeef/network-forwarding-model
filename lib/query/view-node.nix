{ lib }:

nodeName: topo:

let
  sanitize = import ./sanitize.nix { inherit lib; };

  nodes = topo.nodes or { };

  fabricHost =
    if topo ? coreNodeName && builtins.isString topo.coreNodeName then
      topo.coreNodeName
    else
      throw "view-node: missing required topo.coreNodeName (fabric host)";

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
        tenantPrefix = "${topo.tenantV4Base}.${toString vid}.0/24";
      in
      (r.dst or "") == tenantPrefix;

  keepRoute6 =
    r:
    if vid == null then
      true
    else
      let
        tenantPrefix = "${topo.ulaPrefix}:${toString vid}::/64";
      in
      (r.dst or "") == tenantPrefix;

  sanitizeTenantRoutes =
    iface:
    if vid == null then
      iface
    else
      iface
      // {
        routes4 = builtins.filter keepRoute4 (iface.routes4 or [ ]);
        routes6 = builtins.filter keepRoute6 (iface.routes6 or [ ]);
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

  routingMaps = topo._routingMaps or null;

in
sanitize {
  node = nodeName;
  interfaces = interfaces;
  routing = routingMaps;
}
