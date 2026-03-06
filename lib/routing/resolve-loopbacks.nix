{ lib }:

let
  stripMask = s:
    let
      parts = lib.splitString "/" (toString s);
    in
    if builtins.length parts == 0 then toString s else builtins.elemAt parts 0;

  hostDst4 = cidr:
    let
      ip = stripMask cidr;
    in
    "${ip}/32";

  hostDst6 = cidr:
    let
      ip = stripMask cidr;
    in
    "${ip}/128";

  membersOf = l: lib.unique ((l.members or [ ]) ++ (builtins.attrNames (l.endpoints or { })));
  endpointsOf = l: l.endpoints or { };

  chooseEndpointKey = linkName: l: nodeName:
    let
      eps = endpointsOf l;
      keys = builtins.attrNames eps;
      exact = if eps ? "${nodeName}" then nodeName else null;
      byLinkName = "${nodeName}-${linkName}";
      byLink = if eps ? "${byLinkName}" then byLinkName else null;
      pref = "${nodeName}-";
      prefKeys = lib.filter (k: lib.hasPrefix pref k) keys;
      byPrefix =
        if prefKeys == [ ]
        then null
        else lib.head (lib.sort (a: b: a < b) prefKeys);
    in
      if exact != null then exact else if byLink != null then byLink else byPrefix;

  getEp = linkName: l: nodeName:
    let
      k = chooseEndpointKey linkName l nodeName;
      eps = endpointsOf l;
    in
      if k == null then { } else (eps.${k} or { });

  findLinkBetween = { links, from, to }:
    let
      names = builtins.attrNames links;
      hits = lib.filter
        (lname:
          let
            l = links.${lname};
            m = membersOf l;
          in lib.elem from m && lib.elem to m)
        names;
    in
      if hits == [ ] then null else lib.head (lib.sort (a: b: a < b) hits);

  nextHop = { links, from, to }:
    let
      lname = findLinkBetween { inherit links from to; };
      l = if lname == null then null else links.${lname};
      epTo = if l == null then { } else getEp lname l to;
    in
      {
        linkName = lname;
        via4 =
          if epTo ? addr4 && epTo.addr4 != null
          then stripMask epTo.addr4
          else null;
        via6 =
          if epTo ? addr6 && epTo.addr6 != null
          then stripMask epTo.addr6
          else null;
      };

  neighborsOf =
    { links, node }:
    let
      names = lib.sort (a: b: a < b) (builtins.attrNames links);
      step = acc: lname:
        let
          l = links.${lname};
          m = membersOf l;
        in
          if lib.elem node m
          then acc ++ (lib.filter (x: x != node) m)
          else acc;
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
                  if n == null
                  then acc
                  else unwind (parent.${n} or null) ([ n ] ++ acc);
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

in
{
  attach = topo:
    let
      links = topo.links or { };
      nodes0 = topo.nodes or { };
      lbs = (topo.compilerIR or { }).routerLoopbacks or { };

      appendIfaceRoutes = node: linkName: add4: add6:
        if linkName == null then node else
        let
          ifs = node.interfaces or { };
          cur = if ifs ? "${linkName}" then ifs.${linkName} else null;

          curRoutes =
            if cur != null && cur ? routes && builtins.isAttrs cur.routes then
              {
                ipv4 = cur.routes.ipv4 or [ ];
                ipv6 = cur.routes.ipv6 or [ ];
              }
            else
              {
                ipv4 = cur.routes4 or [ ];
                ipv6 = cur.routes6 or [ ];
              };

          new4 = if add4 == null then [ ] else add4;
          new6 = if add6 == null then [ ] else add6;
        in
          if cur == null then node else
          node // {
            interfaces = ifs // {
              "${linkName}" = cur // {
                routes = {
                  ipv4 = curRoutes.ipv4 ++ new4;
                  ipv6 = curRoutes.ipv6 ++ new6;
                };
              };
            };
          };

      perNode =
        nodeName:
        let
          dstNodes = builtins.attrNames lbs;

          perDst =
            builtins.foldl'
              (acc: dst:
                if dst == nodeName then acc else
                let
                  path = shortestPath { inherit links; src = nodeName; dst = dst; };
                in
                  if path == null || builtins.length path < 2 then
                    throw "routing(loopbacks): unreachable router identity '${dst}' from '${nodeName}'"
                  else
                    let
                      hop = builtins.elemAt path 1;
                      nh = nextHop { inherit links; from = nodeName; to = hop; };
                      lb = lbs.${dst};

                      r4 =
                        if nh.linkName == null || nh.via4 == null || !(lb ? ipv4) || lb.ipv4 == null
                        then [ ]
                        else [ { dst = hostDst4 (toString lb.ipv4); via4 = nh.via4; proto = "internal"; } ];

                      r6 =
                        if nh.linkName == null || nh.via6 == null || !(lb ? ipv6) || lb.ipv6 == null
                        then [ ]
                        else [ { dst = hostDst6 (toString lb.ipv6); via6 = nh.via6; proto = "internal"; } ];
                    in
                      if nh.linkName == null then acc else
                      acc // {
                        "${nh.linkName}" = {
                          routes4 =
                            (if acc ? "${nh.linkName}" && acc.${nh.linkName} ? routes4
                             then acc.${nh.linkName}.routes4 else [ ]) ++ r4;
                          routes6 =
                            (if acc ? "${nh.linkName}" && acc.${nh.linkName} ? routes6
                             then acc.${nh.linkName}.routes6 else [ ]) ++ r6;
                        };
                      })
              { }
              dstNodes;
        in
          perDst;

      nodes1 =
        lib.mapAttrs
          (n: node:
            let
              perIface = perNode n;
              linkNames = builtins.attrNames perIface;
            in
              builtins.foldl'
                (acc: lname:
                  let v = perIface.${lname};
                  in appendIfaceRoutes acc lname v.routes4 v.routes6)
                node
                linkNames)
          nodes0;

    in
      topo // {
        nodes = nodes1;
        _loopbackResolution = {
          algorithm = "bfs-shortest-path";
          dst = {
            v4 = "host/32";
            v6 = "host/128";
          };
        };
      };
}
