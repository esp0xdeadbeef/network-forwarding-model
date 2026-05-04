{ lib }:

let
  graph = import ./graph.nix { inherit lib; };
  helpers = import ./static-helpers.nix { inherit lib; };
  directWanDefaults = import ./direct-wan-defaults.nix { inherit lib; };
  laneDefaults = import ./lane-defaults.nix { inherit lib; };
  overlayCoreSelection = import ./overlay-core-selection.nix { inherit lib; };
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
    directWanDefaults.apply { inherit node mkRoute4 mkRoute6; };

  addDefaultTowardNearestUplinkCore =
    topo: nodeName: node:
    let
      uplinks = helpers.uplinkCores topo;
      defaultReachabilityCores = overlayCoreSelection.nonOverlayUplinkCores topo uplinks;
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
        ) defaultReachabilityCores;

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
    laneDefaults.addDownstreamSelectorPolicyDefaults {
      inherit
        topo
        nodeName
        node
        laneAccessNodeNameFromLinkName
        mkRoute4
        mkRoute6
        ;
    };

  addPolicyUpstreamSelectorLaneDefaults =
    topo: nodeName: node:
    laneDefaults.addPolicyUpstreamSelectorDefaults {
      inherit
        topo
        nodeName
        node
        laneAccessNodeNameFromLinkName
        mkRoute4
        mkRoute6
        ;
    };
    in
    {
      addDefaultTowardNearestUplinkCore = addDefaultTowardNearestUplinkCore topo nodeName node;
      addDownstreamSelectorPolicyLaneDefaults = addDownstreamSelectorPolicyLaneDefaults topo nodeName node;
      addPolicyUpstreamSelectorLaneDefaults = addPolicyUpstreamSelectorLaneDefaults topo nodeName node;
      addDirectWanDefaults = addDirectWanDefaults topo nodeName node;
    };
}
