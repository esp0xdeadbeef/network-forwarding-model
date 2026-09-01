{
  lib,
  self ? {
    outPath = ./.;
  },
  ...
}:

let
  common = import ./guard-common.nix { inherit lib self; };
  inherit (common)
    helpers
    link
    linkUplinkNames
    roleOf
    sortedUnique
    ;

  isDefaultRoute =
    route:
    (route.intent.kind or null) == "default-reachability"
    || (
      (route.proto or null) == "default"
      && ((route.dst or null) == helpers.default4 || (route.dst or null) == helpers.default6)
    );

  ifaceRoutes =
    iface:
    let
      routes = iface.routes or { };
    in
    (routes.ipv4 or [ ]) ++ (routes.ipv6 or [ ]) ++ (iface.routes4 or [ ]) ++ (iface.routes6 or [ ]);

  coreNodeNamesFor =
    topo:
    let
      nodes = topo.nodes or { };
    in
    if builtins.isList (topo.coreNodeNames or null) && topo.coreNodeNames != [ ] then
      sortedUnique topo.coreNodeNames
    else
      sortedUnique (lib.filter (nodeName: roleOf nodes nodeName == "core") (builtins.attrNames nodes));

  linksForSelectorCoreUplink =
    topo: upstreamSelectorName: coreSet: uplinkName:
    let
      links = topo.links or { };
      connectsSelectorAndCore =
        linkName:
        let
          members = link.membersOf (links.${linkName} or { });
        in
        builtins.elem upstreamSelectorName members
        && builtins.any (member: coreSet.${toString member} or false) members;
      uplinkMatches =
        linkName:
        let
          names = linkUplinkNames (links.${linkName} or { });
        in
        names == [ ] || builtins.elem uplinkName names;
    in
    lib.filter (linkName: connectsSelectorAndCore linkName && uplinkMatches linkName) (
      builtins.attrNames links
    );

  selectorDefaultRoutes =
    selectorNode:
    let
      interfaces = selectorNode.interfaces or { };
    in
    lib.concatMap (
      ifName:
      map (route: {
        inherit ifName route;
      }) (lib.filter isDefaultRoute (ifaceRoutes (interfaces.${ifName} or { })))
    ) (builtins.attrNames interfaces);

  formatPair =
    pair:
    let
      tenants =
        if pair.tenants == [ ] then "<unknown-tenant>" else builtins.concatStringsSep "," pair.tenants;
    in
    "access=${pair.accessName} tenant=${tenants} uplink=${pair.uplinkName}";
in
{
  inherit
    isDefaultRoute
    ifaceRoutes
    coreNodeNamesFor
    linksForSelectorCoreUplink
    selectorDefaultRoutes
    formatPair
    ;
}
