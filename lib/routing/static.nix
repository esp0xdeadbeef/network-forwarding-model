{ lib }:

let
  cidr = import ../fabric/invariants/cidr-utils.nix { inherit lib; };

  default4 = "0.0.0.0/0";
  default6 = "::/0";

  stripMask =
    addr:
    if addr == null then
      null
    else
      builtins.elemAt (lib.splitString "/" (toString addr)) 0;

  splitCidr =
    cidrStr:
    let
      parts = lib.splitString "/" (toString cidrStr);
    in
    if builtins.length parts != 2 then
      throw "routing(static): invalid CIDR '${toString cidrStr}'"
    else
      {
        ip = builtins.elemAt parts 0;
        prefix = lib.toInt (builtins.elemAt parts 1);
      };

  intToV4 =
    n:
    let
      o0 = builtins.div n (256 * 256 * 256);
      r0 = n - o0 * (256 * 256 * 256);
      o1 = builtins.div r0 (256 * 256);
      r1 = r0 - o1 * (256 * 256);
      o2 = builtins.div r1 256;
      o3 = r1 - o2 * 256;
    in
    lib.concatStringsSep "." (map toString [ o0 o1 o2 o3 ]);

  canonicalCidr =
    cidrStr:
    let
      c = splitCidr cidrStr;
      r = cidr.cidrRange cidrStr;
      base =
        if r.family == 4 then
          intToV4 r.start
        else
          toString r.start;
    in
    "${base}/${toString c.prefix}";

  mkRoute4 =
    dst: via4: proto: {
      dst = canonicalCidr dst;
      inherit via4 proto;
    };

  mkRoute6 =
    dst: via6: proto: {
      dst = canonicalCidr dst;
      inherit via6 proto;
    };

  membersOf = l: lib.unique ((l.members or [ ]) ++ (builtins.attrNames (l.endpoints or { })));
  endpointsOf = l: l.endpoints or { };

  chooseEndpointKey =
    linkName: l: nodeName:
    let
      eps = endpointsOf l;
      exact = if eps ? "${nodeName}" then nodeName else null;
      byLinkName = "${nodeName}-${linkName}";
      byLink = if eps ? "${byLinkName}" then byLinkName else null;
      bySemanticName =
        let
          nm = l.name or null;
          k = if nm == null then null else "${nodeName}-${nm}";
        in
        if k != null && eps ? "${k}" then k else null;
    in
    if exact != null then exact else if byLink != null then byLink else bySemanticName;

  getEp =
    linkName: link: node:
    let
      eps = endpointsOf link;
      k = chooseEndpointKey linkName link node;
    in
    if k == null then { } else (eps.${k} or { });

  neighborsOf =
    { links, node }:
    let
      names = lib.sort (a: b: a < b) (builtins.attrNames links);
      step =
        acc: lname:
        let
          l = links.${lname};
          m = membersOf l;
        in
        if lib.elem node m then acc ++ (lib.filter (x: x != node) m) else acc;
    in
    lib.sort (a: b: a < b) (lib.unique (builtins.foldl' step [ ] names));

  shortestPath =
    { links, src, dst }:
    if src == dst then
      [ src ]
    else
      let
        bfs =
          { queue, visited, parent }:
          if queue == [ ] then
            null
          else
            let
              cur = lib.head queue;
              rest = lib.tail queue;
            in
            if cur == dst then
              let
                unwind =
                  n: acc:
                  if n == null then acc else unwind (parent.${n} or null) ([ n ] ++ acc);
              in
              unwind dst [ ]
            else
              let
                ns = neighborsOf { inherit links; node = cur; };
                fresh = lib.filter (n: !(visited ? "${n}")) ns;
                visited' =
                  builtins.foldl'
                    (acc: n: acc // { "${n}" = true; })
                    visited
                    fresh;
                parent' =
                  builtins.foldl'
                    (acc: n: acc // { "${n}" = cur; })
                    parent
                    fresh;
              in
              bfs { queue = rest ++ fresh; visited = visited'; parent = parent'; };
      in
      bfs { queue = [ src ]; visited = { "${src}" = true; }; parent = { }; };

  findLinkBetween =
    { links, a, b }:
    let
      names = builtins.attrNames links;
      hits =
        lib.filter
          (lname:
            let
              l = links.${lname};
            in
            lib.elem a (membersOf l) && lib.elem b (membersOf l))
          names;
    in
    if hits == [ ] then null else lib.head (lib.sort (x: y: x < y) hits);

  nextHop =
    { links, from, to }:
    let
      lname = findLinkBetween { inherit links; a = from; b = to; };
      l = if lname == null then null else links.${lname};
      ep = if l == null then { } else getEp lname l to;
    in
    {
      linkName = lname;
      via4 = if ep ? addr4 && ep.addr4 != null then stripMask ep.addr4 else null;
      via6 = if ep ? addr6 && ep.addr6 != null then stripMask ep.addr6 else null;
    };

  uplinkCores =
    topo:
    if topo ? uplinkCoreNames && builtins.isList topo.uplinkCoreNames then
      topo.uplinkCoreNames
    else
      [ ];

  routeKey =
    r:
    "${toString (r.dst or "")}|${toString (r.via4 or "")}|${toString (r.via6 or "")}|${toString (r.proto or "")}";

  dedupeRoutes =
    routes:
    builtins.attrValues (
      builtins.foldl'
        (acc: r: acc // { "${routeKey r}" = r; })
        { }
        routes
    );

  addRoutesOnLink =
    node: linkName: add4: add6:
    let
      ifs = node.interfaces or { };
      cur = ifs.${linkName} or { };
      curRoutes =
        if cur ? routes && builtins.isAttrs cur.routes then
          {
            ipv4 = cur.routes.ipv4 or [ ];
            ipv6 = cur.routes.ipv6 or [ ];
          }
        else
          {
            ipv4 = cur.routes4 or [ ];
            ipv6 = cur.routes6 or [ ];
          };
    in
    node // {
      interfaces = ifs // {
        "${linkName}" = cur // {
          routes = {
            ipv4 = dedupeRoutes (curRoutes.ipv4 ++ add4);
            ipv6 = dedupeRoutes (curRoutes.ipv6 ++ add6);
          };
        };
      };
    };

  isNetworkAttr =
    name: v:
    builtins.isAttrs v
    && (v ? ipv4 || v ? ipv6)
    && !(lib.elem name [
      "role"
      "interfaces"
      "networks"
      "containers"
      "uplinks"
    ]);

  networksOf =
    node:
    if node ? networks && builtins.isAttrs node.networks then
      let
        nets = node.networks;
      in
      if nets ? ipv4 || nets ? ipv6 then
        { default = nets; }
      else
        nets
    else
      lib.filterAttrs isNetworkAttr node;

  allNodeNames = topo: builtins.attrNames (topo.nodes or { });

  ownConnectedPrefixes =
    node:
    let
      ifs = node.interfaces or { };
      ifNames = builtins.attrNames ifs;
      fromIfaces =
        lib.concatMap (
          ifName:
          let
            iface = ifs.${ifName};
          in
          lib.flatten [
            (lib.optional (iface ? addr4 && iface.addr4 != null) { family = 4; dst = canonicalCidr iface.addr4; })
            (lib.optional (iface ? addr6 && iface.addr6 != null) { family = 6; dst = canonicalCidr iface.addr6; })
            (lib.optional (iface ? addr6Public && iface.addr6Public != null) { family = 6; dst = canonicalCidr iface.addr6Public; })
            (map (p: { family = 6; dst = canonicalCidr p; }) (iface.ra6Prefixes or [ ]))
          ]
        ) ifNames;

      nets = networksOf node;
      netNames = builtins.attrNames nets;
      fromNets =
        lib.concatMap (
          netName:
          let
            net = nets.${netName};
          in
          lib.flatten [
            (lib.optional (net ? ipv4 && net.ipv4 != null) { family = 4; dst = canonicalCidr net.ipv4; })
            (lib.optional (net ? ipv6 && net.ipv6 != null) { family = 6; dst = canonicalCidr net.ipv6; })
          ]
        ) netNames;
    in
    builtins.foldl'
      (acc: e: acc // { "${toString e.family}|${e.dst}" = true; })
      { }
      (fromIfaces ++ fromNets);

  p2pPrefixesForNode =
    node:
    let
      ifs = node.interfaces or { };
      ifNames = builtins.attrNames ifs;
    in
    builtins.foldl'
      (acc: ifName:
        let
          iface = ifs.${ifName};
        in
        if (iface.kind or null) != "p2p" then
          acc
        else
          acc
          // (lib.optionalAttrs (iface ? addr4 && iface.addr4 != null) {
            "4|${canonicalCidr iface.addr4}" = {
              family = 4;
              dst = canonicalCidr iface.addr4;
            };
          })
          // (lib.optionalAttrs (iface ? addr6 && iface.addr6 != null) {
            "6|${canonicalCidr iface.addr6}" = {
              family = 6;
              dst = canonicalCidr iface.addr6;
            };
          }))
      { }
      ifNames;

  tenantPrefixesForNode =
    node:
    let
      nets = networksOf node;
      netNames = builtins.attrNames nets;
    in
    builtins.foldl'
      (acc: netName:
        let
          net = nets.${netName};
        in
        acc
        // (lib.optionalAttrs (net ? ipv4 && net.ipv4 != null) {
          "4|${canonicalCidr net.ipv4}" = {
            family = 4;
            dst = canonicalCidr net.ipv4;
          };
        })
        // (lib.optionalAttrs (net ? ipv6 && net.ipv6 != null) {
          "6|${canonicalCidr net.ipv6}" = {
            family = 6;
            dst = canonicalCidr net.ipv6;
          };
        }))
      { }
      netNames;

  buildP2pAggregate =
    topo: family:
    let
      pool = topo.p2p-pool or { };
    in
    if family == 4 then pool.ipv4 or null else pool.ipv6 or null;

  buildTenantAggregate =
    topo: family:
    if family == 4 then
      if topo ? tenantV4Base then "${topo.tenantV4Base}.0.0/16" else null
    else if topo ? ulaPrefix then
      "${topo.ulaPrefix}::/56"
    else
      null;

  aggregationMode =
    topo:
    if topo ? aggregation && builtins.isAttrs topo.aggregation && topo.aggregation ? mode then
      topo.aggregation.mode
    else
      "none";

  aggregatePrefixesForNode =
    topo: nodeName:
    let
      mode = aggregationMode topo;
      node = topo.nodes.${nodeName};
      ownSet = ownConnectedPrefixes node;

      mkOne =
        dstEntry:
        let
          path = shortestPath { links = topo.links or { }; src = nodeName; dst = dstEntry.owner; };
        in
        if path == null || builtins.length path < 2 then
          null
        else
          let
            hop = builtins.elemAt path 1;
            nh = nextHop { links = topo.links or { }; from = nodeName; to = hop; };
          in
          if nh.linkName == null then
            null
          else if dstEntry.family == 4 && nh.via4 == null then
            null
          else if dstEntry.family == 6 && nh.via6 == null then
            null
          else
            dstEntry // {
              hopNode = hop;
              linkName = nh.linkName;
              via4 = nh.via4;
              via6 = nh.via6;
            };

      remoteP2p =
        lib.concatMap (
          other:
          if other == nodeName then
            [ ]
          else
            map
              (x: x // { owner = other; kind = "p2p"; })
              (builtins.attrValues (p2pPrefixesForNode topo.nodes.${other}))
        ) (allNodeNames topo);

      remoteTenant =
        lib.concatMap (
          other:
          if other == nodeName then
            [ ]
          else
            map
              (x: x // { owner = other; kind = "tenant"; })
              (builtins.attrValues (tenantPrefixesForNode topo.nodes.${other}))
        ) (allNodeNames topo);

      remote =
        lib.filter
          (e: !(ownSet ? "${toString e.family}|${e.dst}"))
          (remoteP2p ++ remoteTenant);

      resolved = lib.filter (x: x != null) (map mkOne remote);

      perNextHopKey =
        e:
        "${e.linkName}|${toString e.family}|${toString (e.via4 or "")}|${toString (e.via6 or "")}|${e.kind}";

      grouped =
        builtins.foldl'
          (acc: e: acc // { "${perNextHopKey e}" = (acc.${perNextHopKey e} or [ ]) ++ [ e ]; })
          { }
          resolved;

      buildRoutesForGroup =
        es:
        let
          sample = builtins.head es;
          rawRoutes =
            if sample.family == 4 then
              map (e: mkRoute4 e.dst e.via4 "internal") es
            else
              map (e: mkRoute6 e.dst e.via6 "internal") es;

          aggDst =
            if mode == "none" then
              null
            else if sample.kind == "p2p" then
              buildP2pAggregate topo sample.family
            else
              buildTenantAggregate topo sample.family;

          aggRoute =
            if aggDst == null then
              [ ]
            else if sample.family == 4 then
              [ (mkRoute4 aggDst sample.via4 "internal") ]
            else
              [ (mkRoute6 aggDst sample.via6 "internal") ];
        in
        {
          linkName = sample.linkName;
          routes4 =
            if sample.family == 4 then
              dedupeRoutes (rawRoutes ++ aggRoute)
            else
              [ ];
          routes6 =
            if sample.family == 6 then
              dedupeRoutes (rawRoutes ++ aggRoute)
            else
              [ ];
        };

      perLink =
        builtins.foldl'
          (acc: g:
            let
              built = buildRoutesForGroup g;
            in
            acc // {
              "${built.linkName}" = {
                routes4 = dedupeRoutes ((acc.${built.linkName}.routes4 or [ ]) ++ built.routes4);
                routes6 = dedupeRoutes ((acc.${built.linkName}.routes6 or [ ]) ++ built.routes6);
              };
            })
          { }
          (builtins.attrValues grouped);
    in
    perLink;

  addInternalRoutes =
    topo: nodeName: node:
    let
      perLink = aggregatePrefixesForNode topo nodeName;
      linkNames = builtins.attrNames perLink;
    in
    builtins.foldl'
      (acc: linkName:
        let
          add = perLink.${linkName};
        in
        addRoutesOnLink acc linkName add.routes4 add.routes6)
      node
      linkNames;

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
            if (iface.kind or null) == "wan" && (iface.gateway or false) && (iface.peerAddr4 or null) != null then
              [ (mkRoute4 default4 (stripMask iface.peerAddr4) "uplink") ]
            else if (iface.kind or null) == "wan" && (iface.gateway or false) && (iface.addr4 or null) != null then
              [ { dst = default4; proto = "uplink"; } ]
            else
              [ ];

          add6 =
            if (iface.kind or null) == "wan" && (iface.gateway or false) && (iface.peerAddr6 or null) != null then
              [ (mkRoute6 default6 (stripMask iface.peerAddr6) "uplink") ]
            else if (iface.kind or null) == "wan" && (iface.gateway or false) && (iface.addr6 or null) != null then
              [ { dst = default6; proto = "uplink"; } ]
            else
              [ ];
        in
        if add4 == [ ] && add6 == [ ] then acc else addRoutesOnLink acc ifName add4 add6;
    in
    builtins.foldl' step node ifNames;

  addDefaultTowardNearestUplinkCore =
    topo: nodeName: node:
    let
      uplinks = uplinkCores topo;
    in
    if uplinks == [ ] || lib.elem nodeName uplinks then
      node
    else
      let
        reachable =
          lib.filter
            (u:
              let
                p = shortestPath { links = topo.links or { }; src = nodeName; dst = u; };
              in
              p != null && builtins.length p >= 2)
            uplinks;

        target =
          if reachable == [ ] then
            null
          else
            builtins.elemAt (lib.sort (a: b: a < b) reachable) 0;
      in
      if target == null then
        node
      else
        let
          path = shortestPath { links = topo.links or { }; src = nodeName; dst = target; };
          hop = builtins.elemAt path 1;
          nh = nextHop { links = topo.links or { }; from = nodeName; to = hop; };
          add4 = if nh.via4 == null then [ ] else [ (mkRoute4 default4 nh.via4 "default") ];
          add6 = if nh.via6 == null then [ ] else [ (mkRoute6 default6 nh.via6 "default") ];
        in
        if nh.linkName == null then node else addRoutesOnLink node nh.linkName add4 add6;

in
{
  attach =
    topo:
    let
      nodes0 = topo.nodes or { };
      nodes1 =
        lib.mapAttrs
          (n: node:
            let
              n1 = addInternalRoutes topo n node;
              n2 = addDefaultTowardNearestUplinkCore topo n n1;
              n3 = addDirectWanDefaults topo n n2;
            in
            n3)
          nodes0;
    in
    topo // { nodes = nodes1; };
}
