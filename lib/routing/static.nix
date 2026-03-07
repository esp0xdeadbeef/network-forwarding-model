{ lib }:

let
  graph = import ./graph.nix { inherit lib; };
  helpers = import ./static-helpers.nix { inherit lib; };

  remotePrefixesOfKind =
    topo: nodeName: kind:
    let
      prefixSetFor =
        otherNode:
        if kind == "p2p" then
          builtins.attrValues (helpers.prefixSetFromP2pIfaces otherNode)
        else
          builtins.attrValues (helpers.prefixSetFromTenantNetworks otherNode);

      perNode =
        other:
        if other == nodeName then
          [ ]
        else
          map (
            x:
            x
            // {
              owner = other;
              inherit kind;
            }
          ) (prefixSetFor topo.nodes.${other});
    in
    lib.concatMap perNode (helpers.allNodeNames topo);

  resolveRemotePrefix =
    topo: nodeName: dstEntry:
    let
      path = graph.shortestPath {
        links = topo.links or { };
        src = nodeName;
        dst = dstEntry.owner;
      };
    in
    if path == null || builtins.length path < 2 then
      null
    else
      let
        hop = builtins.elemAt path 1;
        nh = graph.nextHop {
          links = topo.links or { };
          stripMask = helpers.stripMask;
          from = nodeName;
          to = hop;
        };
      in
      if nh.linkName == null then
        null
      else if dstEntry.family == 4 && nh.via4 == null then
        null
      else if dstEntry.family == 6 && nh.via6 == null then
        null
      else
        dstEntry
        // {
          hopNode = hop;
          linkName = nh.linkName;
          via4 = nh.via4;
          via6 = nh.via6;
        };

  buildRoutesForGroup =
    topo: mode: es:
    let
      sample = builtins.head es;
      rawRoutes =
        if sample.family == 4 then
          map (e: helpers.mkRoute4 e.dst e.via4 "internal") es
        else
          map (e: helpers.mkRoute6 e.dst e.via6 "internal") es;

      aggDst =
        if mode == "none" then
          null
        else if sample.kind == "p2p" then
          helpers.buildP2pAggregate topo sample.family
        else
          helpers.buildTenantAggregate topo sample.family;

      aggRoute =
        if aggDst == null then
          [ ]
        else if sample.family == 4 then
          [ (helpers.mkRoute4 aggDst sample.via4 "internal") ]
        else
          [ (helpers.mkRoute6 aggDst sample.via6 "internal") ];
    in
    {
      linkName = sample.linkName;
      routes4 = if sample.family == 4 then helpers.dedupeRoutes (rawRoutes ++ aggRoute) else [ ];
      routes6 = if sample.family == 6 then helpers.dedupeRoutes (rawRoutes ++ aggRoute) else [ ];
    };

  aggregatePrefixesForNode =
    topo: nodeName:
    let
      mode = helpers.aggregationMode topo;
      node = topo.nodes.${nodeName};
      ownSet = helpers.ownConnectedPrefixes node;

      remote = lib.filter (e: !(ownSet ? "${toString e.family}|${e.dst}")) (
        (remotePrefixesOfKind topo nodeName "p2p") ++ (remotePrefixesOfKind topo nodeName "tenant")
      );

      resolved = lib.filter (x: x != null) (map (resolveRemotePrefix topo nodeName) remote);

      perNextHopKey =
        e:
        "${e.linkName}|${toString e.family}|${toString (e.via4 or "")}|${toString (e.via6 or "")}|${e.kind}";

      grouped = builtins.foldl' (
        acc: e: acc // { "${perNextHopKey e}" = (acc.${perNextHopKey e} or [ ]) ++ [ e ]; }
      ) { } resolved;

      perLink = builtins.foldl' (
        acc: g:
        let
          built = buildRoutesForGroup topo mode g;
        in
        acc
        // {
          "${built.linkName}" = {
            routes4 = helpers.dedupeRoutes ((acc.${built.linkName}.routes4 or [ ]) ++ built.routes4);
            routes6 = helpers.dedupeRoutes ((acc.${built.linkName}.routes6 or [ ]) ++ built.routes6);
          };
        }
      ) { } (builtins.attrValues grouped);
    in
    perLink;

  addInternalRoutes =
    topo: nodeName: node:
    let
      perLink = aggregatePrefixesForNode topo nodeName;
      linkNames = builtins.attrNames perLink;
    in
    builtins.foldl' (
      acc: linkName:
      let
        add = perLink.${linkName};
      in
      helpers.addRoutesOnLink acc linkName add.routes4 add.routes6
    ) node linkNames;

  addDirectWanDefaults =
    topo: nodeName: node:
    let
      ifs = node.interfaces or { };
      ifNames = builtins.attrNames ifs;

      step =
        acc: ifName:
        let
          iface = ifs.${ifName};

          add4 =
            if
              (iface.kind or null) == "wan" && (iface.gateway or false) && (iface.peerAddr4 or null) != null
            then
              [ (helpers.mkRoute4 helpers.default4 (helpers.stripMask iface.peerAddr4) "uplink") ]
            else if
              (iface.kind or null) == "wan" && (iface.gateway or false) && (iface.addr4 or null) != null
            then
              [
                {
                  dst = helpers.default4;
                  proto = "uplink";
                }
              ]
            else
              [ ];

          add6 =
            if
              (iface.kind or null) == "wan" && (iface.gateway or false) && (iface.peerAddr6 or null) != null
            then
              [ (helpers.mkRoute6 helpers.default6 (helpers.stripMask iface.peerAddr6) "uplink") ]
            else if
              (iface.kind or null) == "wan" && (iface.gateway or false) && (iface.addr6 or null) != null
            then
              [
                {
                  dst = helpers.default6;
                  proto = "uplink";
                }
              ]
            else
              [ ];
        in
        if add4 == [ ] && add6 == [ ] then acc else helpers.addRoutesOnLink acc ifName add4 add6;
    in
    builtins.foldl' step node ifNames;

  addDefaultTowardNearestUplinkCore =
    topo: nodeName: node:
    let
      uplinks = helpers.uplinkCores topo;
    in
    if uplinks == [ ] || lib.elem nodeName uplinks then
      node
    else
      let
        reachable = lib.filter (
          u:
          let
            p = graph.shortestPath {
              links = topo.links or { };
              src = nodeName;
              dst = u;
            };
          in
          p != null && builtins.length p >= 2
        ) uplinks;

        target = if reachable == [ ] then null else builtins.elemAt (lib.sort (a: b: a < b) reachable) 0;
      in
      if target == null then
        node
      else
        let
          path = graph.shortestPath {
            links = topo.links or { };
            src = nodeName;
            dst = target;
          };
          hop = builtins.elemAt path 1;
          nh = graph.nextHop {
            links = topo.links or { };
            stripMask = helpers.stripMask;
            from = nodeName;
            to = hop;
          };
          add4 = if nh.via4 == null then [ ] else [ (helpers.mkRoute4 helpers.default4 nh.via4 "default") ];
          add6 = if nh.via6 == null then [ ] else [ (helpers.mkRoute6 helpers.default6 nh.via6 "default") ];
        in
        if nh.linkName == null then node else helpers.addRoutesOnLink node nh.linkName add4 add6;

in
{
  attach =
    topo:
    let
      nodes0 = topo.nodes or { };
      nodes1 = lib.mapAttrs (
        n: node:
        let
          n1 = addInternalRoutes topo n node;
          n2 = addDefaultTowardNearestUplinkCore topo n n1;
          n3 = addDirectWanDefaults topo n n2;
        in
        n3
      ) nodes0;
    in
    topo // { nodes = nodes1; };
}
