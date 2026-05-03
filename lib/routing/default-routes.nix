{ lib }:

let
  graph = import ./graph.nix { inherit lib; };
  helpers = import ./static-helpers.nix { inherit lib; };
in
{
  apply =
    {
      topo,
      nodeName,
      node,
      nextHopWithPreferredUplinks,
      laneAccessNodeNameFromLinkName,
      mkRoute4,
      mkRoute6,
    }:
    let
  addDirectWanDefaults =
    topo: nodeName: node:
    let
      ifs = node.interfaces or { };
      ifNames = builtins.attrNames ifs;

      step =
        acc: ifName:
        let
          iface = ifs.${ifName};

          add4Prefixes =
            if (iface.peerAddr4 or null) == null then
              [ ]
            else
              map (
                dst:
                mkRoute4 {
                  inherit dst;
                  via4 = helpers.stripMask iface.peerAddr4;
                  proto = "uplink";
                  intentKind = "uplink-learned-reachability";
                }
              ) (iface.uplinkRoutes4 or [ ]);

          add6Prefixes =
            if (iface.peerAddr6 or null) == null then
              [ ]
            else
              map (
                dst:
                mkRoute6 {
                  inherit dst;
                  via6 = helpers.stripMask iface.peerAddr6;
                  proto = "uplink";
                  intentKind = "uplink-learned-reachability";
                }
              ) (iface.uplinkRoutes6 or [ ]);

          add4Default =
            if
              (iface.kind or null) == "wan" && (iface.gateway or false) && (iface.peerAddr4 or null) != null
            then
              [
                (mkRoute4 {
                  dst = helpers.default4;
                  via4 = helpers.stripMask iface.peerAddr4;
                  proto = "default";
                  intentKind = "default-reachability";
                })
              ]
            else if
              (iface.kind or null) == "wan" && (iface.gateway or false) && (iface.addr4 or null) != null
            then
              [
                {
                  dst = helpers.default4;
                  proto = "default";
                  intent = {
                    kind = "default-reachability";
                  };
                }
              ]
            else
              [ ];

          add6Default =
            if
              (iface.kind or null) == "wan" && (iface.gateway or false) && (iface.peerAddr6 or null) != null
            then
              [
                (mkRoute6 {
                  dst = helpers.default6;
                  via6 = helpers.stripMask iface.peerAddr6;
                  proto = "default";
                  intentKind = "default-reachability";
                })
              ]
            else if
              (iface.kind or null) == "wan" && (iface.gateway or false) && (iface.addr6 or null) != null
            then
              [
                {
                  dst = helpers.default6;
                  proto = "default";
                  intent = {
                    kind = "default-reachability";
                  };
                }
              ]
            else
              [ ];

          add4 = add4Prefixes ++ add4Default;
          add6 = add6Prefixes ++ add6Default;
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
          nh = nextHopWithPreferredUplinks {
            inherit topo;
            from = nodeName;
            to = hop;
            preferredUplinks = topo.uplinkNames or [ ];
          };
          add4 =
            if nh.via4 == null then
              [ ]
            else
              [
                (mkRoute4 {
                  dst = helpers.default4;
                  via4 = nh.via4;
                  proto = "default";
                  intentKind = "default-reachability";
                })
              ];
          add6 =
            if nh.via6 == null then
              [ ]
            else
              [
                (mkRoute6 {
                  dst = helpers.default6;
                  via6 = nh.via6;
                  proto = "default";
                  intentKind = "default-reachability";
                })
              ];
        in
        if nh.linkName == null then node else helpers.addRoutesOnLink node nh.linkName add4 add6;

  addDownstreamSelectorPolicyLaneDefaults =
    topo: nodeName: node:
    let
      policyNodeName = topo.policyNodeName or null;
      role = node.role or null;
      links = topo.links or { };
      laneLinks =
        if role != "downstream-selector" || policyNodeName == null then
          [ ]
        else
          lib.filter (
            linkName:
            let
              linkObj = links.${linkName};
              members = graph.membersOf linkObj;
            in
            lib.elem nodeName members
            && lib.elem policyNodeName members
            && laneAccessNodeNameFromLinkName linkName != null
          ) (lib.sort (a: b: a < b) (builtins.attrNames links));

      addLane =
        acc: linkName:
        let
          linkObj = links.${linkName};
          epTo = graph.getEp linkName linkObj policyNodeName;
          via4 = if epTo ? addr4 && epTo.addr4 != null then helpers.stripMask epTo.addr4 else null;
          via6 = if epTo ? addr6 && epTo.addr6 != null then helpers.stripMask epTo.addr6 else null;
          add4 =
            if via4 == null then
              [ ]
            else
              [
                (mkRoute4 {
                  dst = helpers.default4;
                  inherit via4;
                  proto = "default";
                  intentKind = "default-reachability";
                })
              ];
          add6 =
            if via6 == null then
              [ ]
            else
              [
                (mkRoute6 {
                  dst = helpers.default6;
                  inherit via6;
                  proto = "default";
                  intentKind = "default-reachability";
                })
              ];
        in
        helpers.addRoutesOnLink acc linkName add4 add6;
    in
    builtins.foldl' addLane node laneLinks;
    in
    {
      addDefaultTowardNearestUplinkCore = addDefaultTowardNearestUplinkCore topo nodeName node;
      addDownstreamSelectorPolicyLaneDefaults = addDownstreamSelectorPolicyLaneDefaults topo nodeName node;
      addDirectWanDefaults = addDirectWanDefaults topo nodeName node;
    };
}
