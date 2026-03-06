{ lib }:

let
  default4 = "0.0.0.0/0";
  default6 = "::/0";

  stripMask = addr:
    if addr == null then null else builtins.elemAt (lib.splitString "/" addr) 0;

  mkRoute4 = dst: via4: { inherit dst via4; };
  mkRoute6 = dst: via6: { inherit dst via6; };

  membersOf = l: lib.unique ((l.members or [ ]) ++ (builtins.attrNames (l.endpoints or { })));
  endpointsOf = l: l.endpoints or { };
  getEp = linkName: link: node: (endpointsOf link).${node} or { };

  isWanLink = l: (l.kind or null) == "wan";
  isP2pLink = l: (l.kind or null) == "p2p";

  neighborsOf =
    { links, node }:
    let
      names = lib.sort (a: b: a < b) (builtins.attrNames links);
      step = acc: lname:
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

                queue' = rest ++ fresh;
              in
              bfs { queue = queue'; visited = visited'; parent = parent'; };
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

  roleOf = topo: nodeName: (topo.nodes.${nodeName}.role or null);

  accessNodes =
    topo:
    builtins.attrNames (lib.filterAttrs (_: n: (n.role or null) == "access") (topo.nodes or { }));

  tenantRanges4 =
    topo:
    let
      nodes = topo.nodes or { };
    in
    lib.concatMap
      (nodeName:
        let
          n = nodes.${nodeName};
          nets = n.networks or { };
        in
        lib.filter (x: x != null) [
          (nets.ipv4 or null)
        ])
      (builtins.attrNames nodes);

  tenantRanges6 =
    topo:
    let
      nodes = topo.nodes or { };
    in
    lib.concatMap
      (nodeName:
        let
          n = nodes.${nodeName};
          nets = n.networks or { };
        in
        lib.filter (x: x != null) [
          (nets.ipv6 or null)
        ])
      (builtins.attrNames nodes);

  uplinkCores =
    topo:
    if topo ? uplinkCoreNames && builtins.isList topo.uplinkCoreNames then
      topo.uplinkCoreNames
    else
      [ ];

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
      r4 = curRoutes.ipv4 ++ add4;
      r6 = curRoutes.ipv6 ++ add6;
    in
    node // {
      interfaces = ifs // {
        "${linkName}" = cur // {
          routes = {
            ipv4 = r4;
            ipv6 = r6;
          };
        };
      };
    };

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
            if (iface.kind or null) == "wan" && (iface.gateway or false) && iface.addr4 != null then
              [ { dst = default4; proto = "uplink"; } ]
            else
              [ ];

          add6 =
            if (iface.kind or null) == "wan" && (iface.gateway or false) && iface.addr6 != null then
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

          add4 = if nh.via4 == null then [ ] else [ (mkRoute4 default4 nh.via4) ];
          add6 = if nh.via6 == null then [ ] else [ (mkRoute6 default6 nh.via6) ];
        in
        if nh.linkName == null then node else addRoutesOnLink node nh.linkName add4 add6;

  addTenantTowardAccess =
    topo: nodeName: node:
    let
      accessNs = accessNodes topo;
      t4 = tenantRanges4 topo;
      t6 = tenantRanges6 topo;
    in
    if accessNs == [ ] then
      node
    else if (roleOf topo nodeName) == "access" then
      node
    else
      let
        a = lib.head (lib.sort (x: y: x < y) accessNs);
        path = shortestPath { links = topo.links or { }; src = nodeName; dst = a; };
      in
      if path == null || builtins.length path < 2 then
        node
      else
        let
          hop = builtins.elemAt path 1;
          nh = nextHop { links = topo.links or { }; from = nodeName; to = hop; };

          add4 = if nh.via4 == null then [ ] else map (p: mkRoute4 p nh.via4) (lib.filter (x: x != null) t4);
          add6 = if nh.via6 == null then [ ] else map (p: mkRoute6 p nh.via6) (lib.filter (x: x != null) t6);
        in
        if nh.linkName == null then node else addRoutesOnLink node nh.linkName add4 add6;

in
{
  attach = topo:
    let
      nodes0 = topo.nodes or { };

      nodes1 =
        lib.mapAttrs
          (n: node:
            let
              n1 = addTenantTowardAccess topo n node;
              n2 = addDefaultTowardNearestUplinkCore topo n n1;
              n3 = addDirectWanDefaults topo n n2;
            in
            n3)
          nodes0;

    in
    topo // {
      nodes = nodes1;
    };
}
