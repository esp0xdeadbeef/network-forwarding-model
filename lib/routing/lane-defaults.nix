{ lib }:

let
  graph = import ./graph.nix { inherit lib; };
  routeBuilder = import ./lane-default-route-builder.nix { inherit lib; };
  laneMetadata = import ./lane-metadata.nix { inherit lib; };
  inherit (routeBuilder) addDefaultsTowardPeer;
  inherit (laneMetadata)
    defaultMetricForLane
    hasUplinkLaneSuffix
    laneAccessNodeNameFromLinkName
    laneUplinkNameFromLinkName
    ;

in
{
  addDownstreamSelectorPolicyDefaults =
    {
      topo,
      nodeName,
      node,
      laneAccessNodeNameFromLinkName,
      mkRoute4,
      mkRoute6,
    }:
    let
      policyNodeName = topo.policyNodeName or null;
      links = topo.links or { };
      role = node.role or null;
      uplinksForAccess =
        accessName:
        lib.unique (
          lib.filter (uplinkName: uplinkName != null) (
            map laneUplinkNameFromLinkName (
              lib.filter (
                linkName:
                let
                  linkObj = links.${linkName};
                  members = graph.membersOf linkObj;
                in
                lib.elem policyNodeName members
                && lib.elem (topo.upstreamSelectorNodeName or null) members
                && laneAccessNodeNameFromLinkName linkName == accessName
                && hasUplinkLaneSuffix linkName
              ) (builtins.attrNames links)
            )
          )
        );
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
    in
    builtins.foldl' (
      acc: linkName:
      let
        accessName = laneAccessNodeNameFromLinkName linkName;
        uplinks = uplinksForAccess accessName;
        uplinkName = if uplinks == [ ] then null else builtins.head (lib.sort (a: b: a < b) uplinks);
      in
      addDefaultsTowardPeer {
        inherit
          links
          linkName
          mkRoute4
          mkRoute6
          ;
        lane = {
          access = accessName;
          uplink = uplinkName;
        };
        node = acc;
        peerNodeName = policyNodeName;
        reason = "policy-derived-default";
      }
    ) node laneLinks;

  addPolicyUpstreamSelectorDefaults =
    {
      topo,
      nodeName,
      node,
      laneAccessNodeNameFromLinkName,
      mkRoute4,
      mkRoute6,
    }:
    let
      policyNodeName = topo.policyNodeName or null;
      selectorNodeName = topo.upstreamSelectorNodeName or null;
      links = topo.links or { };
      role = node.role or null;
      laneLinks =
        if role != "policy" || policyNodeName != nodeName || selectorNodeName == null then
          [ ]
        else
          lib.filter (
            linkName:
            let
              linkObj = links.${linkName};
              members = graph.membersOf linkObj;
            in
            lib.elem policyNodeName members
            && lib.elem selectorNodeName members
            && laneAccessNodeNameFromLinkName linkName != null
            && hasUplinkLaneSuffix linkName
          ) (lib.sort (a: b: a < b) (builtins.attrNames links));
    in
    builtins.foldl' (
      acc: linkName:
      addDefaultsTowardPeer {
        inherit
          links
          linkName
          mkRoute4
          mkRoute6
          ;
        lane = {
          access = laneAccessNodeNameFromLinkName linkName;
          uplink = laneUplinkNameFromLinkName linkName;
        };
        metric = defaultMetricForLane topo linkName;
        node = acc;
        peerNodeName = selectorNodeName;
        reason = "policy-derived-default";
      }
    ) node laneLinks;
}
