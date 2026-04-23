{ lib }:

let
  graph = import ./graph.nix { inherit lib; };

  laneUplinkNameFromLinkName =
    linkName:
    let
      marker = "--uplink-";
      s = toString linkName;
      parts = lib.splitString marker s;
    in
    if builtins.length parts < 2 then null else builtins.elemAt parts ((builtins.length parts) - 1);

  laneAccessNodeNameFromLinkName =
    linkName:
    let
      marker = "--access-";
      s = toString linkName;
      parts = lib.splitString marker s;
      lastPart =
        if builtins.length parts < 2 then null else builtins.elemAt parts ((builtins.length parts) - 1);
      segments = if lastPart == null then [ ] else lib.splitString "--uplink-" lastPart;
    in
    if segments == [ ] then null else builtins.elemAt segments 0;

  strip =
    a:
    let
      s = toString a;
      parts = lib.splitString "/" s;
    in
    if builtins.length parts > 0 then builtins.elemAt parts 0 else s;

  hostDst4 =
    cidr:
    let
      ip0 = strip cidr;
    in
    "${ip0}/32";

  hostDst6 =
    cidr:
    let
      ip0 = strip cidr;
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

  internalIntent = {
    kind = "internal-reachability";
  };

  nextHopWithPreferences =
    {
      links,
      from,
      to,
      preferredUplinks ? [ ],
      preferredAccessNodes ? [ ],
    }:
    let
      candidates = lib.sort (a: b: a < b) (
        lib.filter (
          lname:
          let
            l = links.${lname};
            members = graph.membersOf l;
          in
          lib.elem from members && lib.elem to members
        ) (builtins.attrNames links)
      );

      preferredUplinkSet = lib.unique (map toString (lib.filter (x: x != null) preferredUplinks));
      preferredAccessSet = lib.unique (map toString (lib.filter (x: x != null) preferredAccessNodes));

      preferredUplinkCandidates =
        if preferredUplinkSet == [ ] then
          [ ]
        else
          lib.filter (
            lname:
            let
              uplinkName = laneUplinkNameFromLinkName lname;
            in
            uplinkName != null && builtins.elem uplinkName preferredUplinkSet
          ) candidates;

      preferredAccessCandidates =
        if preferredAccessSet == [ ] then
          [ ]
        else
          lib.filter (
            lname:
            let
              accessNodeName = laneAccessNodeNameFromLinkName lname;
            in
            accessNodeName != null && builtins.elem accessNodeName preferredAccessSet
          ) candidates;

      chosen =
        if preferredUplinkCandidates != [ ] && preferredAccessCandidates != [ ] then
          let
            overlap = lib.filter (
              lname: builtins.elem lname preferredAccessCandidates
            ) preferredUplinkCandidates;
          in
          if overlap != [ ] then builtins.head overlap else builtins.head preferredUplinkCandidates
        else if preferredUplinkCandidates != [ ] then
          builtins.head preferredUplinkCandidates
        else if preferredAccessCandidates != [ ] then
          builtins.head preferredAccessCandidates
        else if candidates != [ ] then
          builtins.head candidates
        else
          null;

      linkObj = if chosen == null then null else links.${chosen};
      epTo = if linkObj == null then { } else graph.getEp chosen linkObj to;
    in
    {
      linkName = chosen;
      via4 = if epTo ? addr4 && epTo.addr4 != null then strip epTo.addr4 else null;
      via6 = if epTo ? addr6 && epTo.addr6 != null then strip epTo.addr6 else null;
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
                  nh = nextHopWithPreferences {
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
                          dst = hostDst4 lb.ipv4;
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
                          dst = hostDst6 lb.ipv6;
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
