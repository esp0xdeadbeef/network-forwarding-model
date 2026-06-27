{ lib, self ? { outPath = ./.; }, ... }:

{ all ? null
, routed
, nodeName ? null
, linkName ? null
, fabricHost ? null
,
}:

let
  sanitize = import ./sanitize.nix { inherit lib self; };
  routes = import (self.outPath + "/implementation/lib/model/routes.nix") { inherit lib self; };

  ifaceRoutes = routes.ifaceRoutes;

  fabricHostResolved =
    if fabricHost != null then
      fabricHost
    else if routed ? coreNodeName && builtins.isString routed.coreNodeName then
      routed.coreNodeName
    else if
      routed ? coreNodeNames && builtins.isList routed.coreNodeNames && routed.coreNodeNames != [ ]
    then
      builtins.elemAt routed.coreNodeNames 0
    else
      throw "node-context: missing required routed.coreNodeName/coreNodeNames (fabric host)";

  requestedNode =
    if nodeName != null then
      nodeName
    else if routed ? coreRoutingNodeName && builtins.isString routed.coreRoutingNodeName then
      routed.coreRoutingNodeName
    else
      fabricHostResolved;

  nodes = routed.nodes or { };

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

  ifaces0 =
    if nodes ? "${requestedNode}" && (nodes.${requestedNode} ? interfaces) then
      nodes.${requestedNode}.interfaces
    else
      { };

  enrichedInterfaces = lib.mapAttrs
    (
      _: iface: sanitizeIface iface
    )
    ifaces0;

  selected =
    if linkName == null then
      enrichedInterfaces
    else if enrichedInterfaces ? "${linkName}" then
      enrichedInterfaces.${linkName}
    else
      throw "node-context: link '${linkName}' not found on node '${requestedNode}'";

in
sanitize {
  node = requestedNode;
  link = linkName;
  config = selected;
}
