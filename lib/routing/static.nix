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
      names = builtins.attrNames links;
      step = acc: lname:
        let
          l = links.${lname};
          m = membersOf l;
        in
        if lib.elem node m then acc ++ (lib.filter (x: x != node) m) else acc;
    in
    lib.unique (builtins.foldl' step [ ] names);

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
            let l = links.${lname};
            in lib.elem a (membersOf l) && lib.elem b (membersOf l))
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
    topo: map (t: t.ipv4) ((topo.domains or { }).tenants or [ ]);

  tenantRanges6 =
    topo: map (t: t.ipv6) ((topo.domains or { }).tenants or [ ]);

  # choose the "WAN gateway" node as the WAN endpoint that has gateway=true (prefer), else any WAN member
  wanGatewayNode =
    topo:
    let
      links = topo.links or { };
      wanNames = lib.filter (n: isWanLink links.${n}) (builtins.attrNames links);
      pick =
        if wanNames == [ ] then null else links.${lib.head wanNames};
    in
    if pick == null then null else
    let
      eps = endpointsOf pick;
      epNames = builtins.attrNames eps;
      gwHits = lib.filter (n: (eps.${n}.gateway or false) == true) epNames;
    in
    if gwHits != [ ] then lib.head (lib.sort (a: b: a < b) gwHits)
    else
      let m = membersOf pick;
      in if m == [ ] then null else lib.head (lib.sort (a: b: a < b) m);

  addRoutesOnLink =
    node: linkName: add4: add6:
    let
      ifs = node.interfaces or { };
      cur = ifs.${linkName} or { };
      r4 = (cur.routes4 or [ ]) ++ add4;
      r6 = (cur.routes6 or [ ]) ++ add6;
    in
    node // {
      interfaces = ifs // {
        "${linkName}" = cur // {
          routes4 = r4;
          routes6 = r6;
        };
      };
    };

  mkBgpModel =
    { topo, links }:
    let
      routing = topo.routing or { };
      bgp = routing.bgp or { };

      localAs = bgp.localAs or 65000;

      peerAsnOf =
        peer:
        let peers = bgp.peers or { };
        in if peers ? "${peer}" then peers.${peer} else bgp.remoteAsDefault or 65001;

      mkNeighbor =
        nodeName: linkName: l:
        let
          m = membersOf l;
          peer =
            let others = lib.filter (x: x != nodeName) m;
            in if others == [ ] then null else lib.head (lib.sort (a: b: a < b) others);

          epPeer = if peer == null then { } else getEp linkName l peer;

          via4 = if epPeer ? addr4 && epPeer.addr4 != null then stripMask epPeer.addr4 else null;
          via6 = if epPeer ? addr6 && epPeer.addr6 != null then stripMask epPeer.addr6 else null;
        in
        if peer == null then null else {
          inherit linkName peer;
          kind =
            if isP2pLink l then "p2p"
            else if isWanLink l then "wan"
            else "lan";
          remoteAs = peerAsnOf peer;
          localAs = bgp.localAsPerNode."${nodeName}" or localAs;
          neighbor4 = via4;
          neighbor6 = via6;
        };

      nodes = topo.nodes or { };
      nodeNames = builtins.attrNames nodes;

      neighbors =
        lib.listToAttrs
          (map
            (n: {
              name = n;
              value =
                lib.filter (x: x != null)
                  (map
                    (lname:
                      let l = links.${lname};
                      in
                      if !(isP2pLink l || isWanLink l) then null
                      else if !(lib.elem n (membersOf l)) then null
                      else mkNeighbor n lname l)
                    (builtins.attrNames links));
            })
            nodeNames);

    in
    {
      mode = "bgp";
      localAs = localAs;
      neighbors = neighbors;
      advertise = {
        tenants4 = tenantRanges4 topo;
        tenants6 = tenantRanges6 topo;
      };
    };

in
{
  attach = topo:
    let
      links = topo.links or { };
      nodes0 = topo.nodes or { };
      nodeNames = builtins.attrNames nodes0;

      gw = wanGatewayNode topo;
      accessNs = accessNodes topo;

      t4 = tenantRanges4 topo;
      t6 = tenantRanges6 topo;

      addDefaultTowardGw =
        nodeName: node:
        if gw == null || nodeName == gw then node else
        let
          path = shortestPath { inherit links; src = nodeName; dst = gw; };
        in
        if path == null || builtins.length path < 2 then node else
        let
          hop = builtins.elemAt path 1;
          nh = nextHop { inherit links; from = nodeName; to = hop; };

          add4 = if nh.via4 == null then [ ] else [ (mkRoute4 default4 nh.via4) ];
          add6 = if nh.via6 == null then [ ] else [ (mkRoute6 default6 nh.via6) ];
        in
        if nh.linkName == null then node else addRoutesOnLink node nh.linkName add4 add6;

      addTenantTowardAccess =
        nodeName: node:
        if accessNs == [ ] then node
        else if (roleOf topo nodeName) == "access" then node
        else
          let
            # pick deterministic access target (first sorted) for tenant routes
            a = lib.head (lib.sort (x: y: x < y) accessNs);
            path = shortestPath { inherit links; src = nodeName; dst = a; };
          in
          if path == null || builtins.length path < 2 then node else
          let
            hop = builtins.elemAt path 1;
            nh = nextHop { inherit links; from = nodeName; to = hop; };

            add4 = if nh.via4 == null then [ ] else map (p: mkRoute4 p nh.via4) (lib.filter (x: x != null) t4);
            add6 = if nh.via6 == null then [ ] else map (p: mkRoute6 p nh.via6) (lib.filter (x: x != null) t6);
          in
          if nh.linkName == null then node else addRoutesOnLink node nh.linkName add4 add6;

      nodes1 =
        lib.mapAttrs
          (n: node:
            let
              n1 = addTenantTowardAccess n node;
              n2 = addDefaultTowardGw n n1;
            in
            n2)
          nodes0;

      bgpModel = mkBgpModel { inherit topo links; };

    in
    topo // {
      nodes = nodes1;
      _bgp = bgpModel;

      _routingMaps = {
        mode = "static";
        defaults = { inherit default4 default6; };
        bgp = bgpModel;
      };
    };
}
