{ lib }:

{
  all ? null,
  routed,
  nodeName ? null,
  linkName ? null,
  fabricHost ? null,
}:

let
  sanitize = import ./sanitize.nix { inherit lib; };
  routes = import ../model/routes.nix { inherit lib; };

  ifaceRoutes = routes.ifaceRoutes;

  fabricHostResolved =
    if fabricHost != null then
      fabricHost
    else if routed ? coreNodeName && builtins.isString routed.coreNodeName then
      routed.coreNodeName
    else
      throw "node-context: missing required routed.coreNodeName (fabric host)";

  requestedNode =
    if nodeName != null then
      nodeName
    else if routed ? coreRoutingNodeName && builtins.isString routed.coreRoutingNodeName then
      routed.coreRoutingNodeName
    else
      fabricHostResolved;

  nodes = routed.nodes or { };

  corePrefix = "${fabricHostResolved}-";
  isCoreContext = lib.hasPrefix corePrefix requestedNode;

  parts = lib.splitString "-" requestedNode;
  lastPart = if parts == [ ] then "" else lib.last parts;

  haveVidSuffix = isCoreContext && (builtins.match "^[0-9]+$" lastPart != null);

  vid = if haveVidSuffix then lib.toInt lastPart else null;

  _assertContextSuffix =
    if isCoreContext && (lib.length parts) >= 4 && !haveVidSuffix then
      throw "node-context: invalid core context node '${requestedNode}': expected numeric vlan suffix"
    else
      true;

  tenant4Dst = if vid == null then null else "${routed.tenantV4Base}.${toString vid}.0/24";
  tenant6Dst = if vid == null then null else "${routed.ulaPrefix}:${toString vid}::/64";

  keepTenantRoute4 = r: if vid == null then true else (r ? dst) && r.dst == tenant4Dst;
  keepTenantRoute6 = r: if vid == null then true else (r ? dst) && r.dst == tenant6Dst;

  scopeTenantRoutes =
    iface:
    if vid == null then
      iface
    else if (iface.kind or null) == "p2p" then
      let
        rs = ifaceRoutes iface;
      in
      iface
      // {
        routes = {
          ipv4 = builtins.filter keepTenantRoute4 rs.ipv4;
          ipv6 = builtins.filter keepTenantRoute6 rs.ipv6;
        };
      }
    else
      iface;

  isDefault4 = r: (r ? dst) && r.dst == "0.0.0.0/0";
  isDefault6 = r: (r ? dst) && r.dst == "::/0";

  isWanIface =
    iface:
    (iface ? kind && iface.kind == "wan")
    || (iface ? carrier && iface.carrier == "wan")
    || (iface ? gateway && iface.gateway == true);

  keepRoute4 = iface: r: (r ? via4) || ((isDefault4 r) && (isWanIface iface));
  keepRoute6 = iface: r: (r ? via6) || ((isDefault6 r) && (isWanIface iface));

  sanitizeIface =
    iface:
    let
      rs = ifaceRoutes iface;
    in
    iface
    // {
      routes = {
        ipv4 = builtins.filter (keepRoute4 iface) rs.ipv4;
        ipv6 = builtins.filter (keepRoute6 iface) rs.ipv6;
      };
    };

  rewriteVlanId =
    iface:
    if vid != null && (iface.kind or null) == "p2p" && (iface.vlanId or null) != null then
      iface // { vlanId = iface.vlanId + vid; }
    else
      iface;

  ifaces0 =
    if nodes ? "${requestedNode}" && (nodes.${requestedNode} ? interfaces) then
      nodes.${requestedNode}.interfaces
    else
      { };

  enrichedInterfaces = lib.mapAttrs (
    _: iface: sanitizeIface (scopeTenantRoutes (rewriteVlanId iface))
  ) ifaces0;

  selected =
    if linkName == null then
      enrichedInterfaces
    else if enrichedInterfaces ? "${linkName}" then
      enrichedInterfaces.${linkName}
    else
      throw "node-context: link '${linkName}' not found on node '${requestedNode}'";

in
builtins.seq _assertContextSuffix (sanitize {
  node = requestedNode;
  link = linkName;
  config = selected;
})
