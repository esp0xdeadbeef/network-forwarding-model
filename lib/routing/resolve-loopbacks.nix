{ lib }:

let
  graph = import ./graph.nix { inherit lib; };
  ip = import ../net/ip-utils.nix { inherit lib; };

  hostDst4 =
    cidr:
    let
      ip0 = ip.stripMask cidr;
    in
    "${ip0}/32";

  hostDst6 =
    cidr:
    let
      ip0 = ip.stripMask cidr;
    in
    "${ip0}/128";

  ifaceRoutes =
    iface:
    if iface ? routes && builtins.isAttrs iface.routes then
      {
        ipv4 = iface.routes.ipv4 or [ ];
        ipv6 = iface.routes.ipv6 or [ ];
      }
    else
      {
        ipv4 = iface.routes4 or [ ];
        ipv6 = iface.routes6 or [ ];
      };

in
{
  attach =
    topo:
    let
      links = topo.links or { };
      nodes0 = topo.nodes or { };
      lbs = (topo.compilerIR or { }).routerLoopbacks or { };

      appendIfaceRoutes =
        node: linkName: add4: add6:
        if linkName == null then
          node
        else
          let
            ifs = node.interfaces or { };
            cur = if ifs ? "${linkName}" then ifs.${linkName} else null;
            curRoutes =
              if cur == null then
                {
                  ipv4 = [ ];
                  ipv6 = [ ];
                }
              else
                ifaceRoutes cur;
            new4 = if add4 == null then [ ] else add4;
            new6 = if add6 == null then [ ] else add6;
          in
          if cur == null then
            node
          else
            node
            // {
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

          perDst = builtins.foldl' (
            acc: dst:
            if dst == nodeName then
              acc
            else
              let
                path = graph.shortestPath {
                  inherit links;
                  src = nodeName;
                  dst = dst;
                };
              in
              if path == null || builtins.length path < 2 then
                throw "routing(loopbacks): unreachable router identity '${dst}' from '${nodeName}'"
              else
                let
                  hop = builtins.elemAt path 1;
                  nh = graph.nextHop {
                    inherit links;
                    from = nodeName;
                    to = hop;
                  };
                  lb = lbs.${dst};

                  r4 =
                    if nh.linkName == null || nh.via4 == null || !(lb ? ipv4) || lb.ipv4 == null then
                      [ ]
                    else
                      [
                        {
                          dst = hostDst4 (toString lb.ipv4);
                          via4 = nh.via4;
                          proto = "internal";
                        }
                      ];

                  r6 =
                    if nh.linkName == null || nh.via6 == null || !(lb ? ipv6) || lb.ipv6 == null then
                      [ ]
                    else
                      [
                        {
                          dst = hostDst6 (toString lb.ipv6);
                          via6 = nh.via6;
                          proto = "internal";
                        }
                      ];
                in
                if nh.linkName == null then
                  acc
                else
                  acc
                  // {
                    "${nh.linkName}" = {
                      routes4 =
                        (if acc ? "${nh.linkName}" && acc.${nh.linkName} ? routes4 then acc.${nh.linkName}.routes4 else [ ])
                        ++ r4;
                      routes6 =
                        (if acc ? "${nh.linkName}" && acc.${nh.linkName} ? routes6 then acc.${nh.linkName}.routes6 else [ ])
                        ++ r6;
                    };
                  }
          ) { } dstNodes;
        in
        perDst;

      nodes1 = lib.mapAttrs (
        n: node:
        let
          perIface = perNode n;
          linkNames = builtins.attrNames perIface;
        in
        builtins.foldl' (
          acc: lname:
          let
            v = perIface.${lname};
          in
          appendIfaceRoutes acc lname v.routes4 v.routes6
        ) node linkNames
      ) nodes0;

    in
    topo
    // {
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
