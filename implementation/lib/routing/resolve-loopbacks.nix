{ lib, self ? { outPath = ./.; }, ... }:

let
  graph = import ./graph.nix { inherit lib self; };
  appendIfaceRoutes = import (self.outPath + "/implementation/lib/routing/loopbacks/append-routes.nix") {
    inherit lib self;
  };
  nextHop = import (self.outPath + "/implementation/lib/routing/loopbacks/next-hop.nix") { inherit lib self; };
  routeFields = import (self.outPath + "/implementation/lib/routing/loopbacks/route-fields.nix") {
    inherit lib self;
  };

  internalIntent = {
    kind = "internal-reachability";
  };

in
{
  attach =
    topo:
    let
      links = topo.links or { };
      nodes0 = topo.nodes or { };

      lbs = builtins.foldl' (
        acc: nodeName:
        let
          node = nodes0.${nodeName};
          lb = node.loopback or null;
        in
        if lb == null || !(builtins.isAttrs lb) then acc else acc // { "${nodeName}" = lb; }
      ) { } (builtins.attrNames nodes0);

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
                  nh = nextHop.withPreferences {
                    inherit links;
                    from = nodeName;
                    to = hop;
                    preferredUplinks =
                      if builtins.elem dst (topo.uplinkCoreNames or [ ]) then topo.uplinkNames or [ ] else [ ];
                    preferredAccessNodes = [ dst ];
                  };
                  lb = lbs.${dst};

                  r4 =
                    if nh.linkName == null || nh.via4 == null || !(lb ? ipv4) || lb.ipv4 == null then
                      [ ]
                    else
                      [
                        {
                          dst = routeFields.hostDst4 lb.ipv4;
                          via4 = nh.via4;
                          proto = "internal";
                          intent = internalIntent;
                          preserveDst = true;
                        }
                      ];

                  r6 =
                    if nh.linkName == null || nh.via6 == null || !(lb ? ipv6) || lb.ipv6 == null then
                      [ ]
                    else
                      [
                        {
                          dst = routeFields.hostDst6 lb.ipv6;
                          via6 = nh.via6;
                          proto = "internal";
                          intent = internalIntent;
                          preserveDst = true;
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
    topo // { nodes = nodes1; };
}
