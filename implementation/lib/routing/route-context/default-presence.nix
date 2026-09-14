{ lib, helpers }:

let
  addDefault = acc: uplinkName: acc // { "${uplinkName}" = true; };

  addNodeWith =
    nodes: predicate:
    builtins.foldl' (
      acc: nodeName:
      builtins.foldl' (
        nodeAcc: uplinkName:
        let
          uplink = ((nodes.${nodeName} or { }).uplinks or { }).${uplinkName} or { };
        in
        if predicate uplink then addDefault nodeAcc uplinkName else nodeAcc
      ) acc (builtins.attrNames ((nodes.${nodeName} or { }).uplinks or { }))
    ) { } (builtins.attrNames nodes);

  addLinkWith =
    links: endpointHasDefault:
    builtins.foldl' (
      acc: linkName:
      let
        link = links.${linkName};
        uplinkName = link.upstream or link.uplink or null;
      in
      if
        uplinkName != null && builtins.any endpointHasDefault (builtins.attrValues (link.endpoints or { }))
      then
        addDefault acc uplinkName
      else
        acc
    );

  # Family-blind default presence. A caller that genuinely means "this uplink
  # has a default in some family" uses this; a caller that builds a per-family
  # multipath member set must not (FS-315, SMS-010).
  uplinkHasDefaultSet =
    nodes: links:
    let
      default6ForNodes = helpers.default6For nodes;
    in
    let
      fromNodes = addNodeWith nodes (
        uplink:
        builtins.elem helpers.default4 (uplink.ipv4 or [ ])
        || builtins.elem default6ForNodes (uplink.ipv6 or [ ])
      );
      fromLinks = addLinkWith links (
        ep:
        let
          e = ep.interfaceData or ep;
        in
        builtins.elem helpers.default4 (e.uplinkRoutes4 or [ ])
        || builtins.elem default6ForNodes (e.uplinkRoutes6 or [ ])
      );
    in
    fromLinks fromNodes (builtins.attrNames links);

  # Family-scoped default presence. A route selection key carries one address
  # family, so multipath membership is decided per family: an egress is a
  # member only when it offers a default for THAT family. The family-blind
  # `uplinkHasDefaultSet` ORs the two families together, so an uplink with an
  # IPv4 default and no IPv6 default would be reported as "has a default" for
  # IPv6 too.
  uplinkHasDefault4Set =
    nodes: links:
    let
      fromNodes = addNodeWith nodes (uplink: builtins.elem helpers.default4 (uplink.ipv4 or [ ]));
      fromLinks = addLinkWith links (
        ep:
        let
          e = ep.interfaceData or ep;
        in
        builtins.elem helpers.default4 (e.uplinkRoutes4 or [ ])
      );
    in
    fromLinks fromNodes (builtins.attrNames links);

  uplinkHasDefault6Set =
    nodes: links:
    let
      default6ForNodes = helpers.default6For nodes;
      fromNodes = addNodeWith nodes (uplink: builtins.elem default6ForNodes (uplink.ipv6 or [ ]));
      fromLinks = addLinkWith links (
        ep:
        let
          e = ep.interfaceData or ep;
        in
        builtins.elem default6ForNodes (e.uplinkRoutes6 or [ ])
      );
    in
    fromLinks fromNodes (builtins.attrNames links);

  # An overlay is not a default in any family by itself: overlay reachability
  # carries peer prefixes (overlayReachability.<name>.routes4/routes6), never a
  # 0.0.0.0/0 or ::/0. Treating "is an overlay" as "has an executable default"
  # in both families admits an egress into a family's multipath member set even
  # when the overlay carries no prefix in that family.
  overlayMembersFor =
    topo: links: family:
    let
      names = lib.unique (
        builtins.attrNames (topo.overlayReachability or { })
        ++ lib.filter (name: name != null) (
          map (linkName: (links.${linkName}.overlay or null)) (builtins.attrNames links)
        )
      );
      routesField = if family == 4 then "routes4" else "routes6";
    in
    lib.listToAttrs (
      lib.filter (entry: entry.value) (
        map (
          name:
          let
            reach = (topo.overlayReachability or { }).${name} or { };
          in
          {
            inherit name;
            value = (reach.${routesField} or [ ]) != [ ];
          }
        ) names
      )
    );
in
{
  inherit
    uplinkHasDefaultSet
    uplinkHasDefault4Set
    uplinkHasDefault6Set
    overlayMembersFor
    ;
}
