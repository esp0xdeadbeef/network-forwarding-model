{ lib }:

let
  graph = import ./graph.nix { inherit lib; };
  helpers = import ./static-helpers.nix { inherit lib; };

  hasUplinkLaneSuffix = linkName: builtins.match ".*--uplink-.+" (toString linkName) != null;

  mkDefaultRoutes =
    {
      epTo,
      mkRoute4,
      mkRoute6,
    }:
    let
      via4 = if epTo ? addr4 && epTo.addr4 != null then helpers.stripMask epTo.addr4 else null;
      via6 = if epTo ? addr6 && epTo.addr6 != null then helpers.stripMask epTo.addr6 else null;
    in
    {
      routes4 =
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
      routes6 =
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
    };

  addDefaultsTowardPeer =
    {
      links,
      node,
      linkName,
      peerNodeName,
      mkRoute4,
      mkRoute6,
    }:
    let
      linkObj = links.${linkName};
      routes = mkDefaultRoutes {
        inherit mkRoute4 mkRoute6;
        epTo = graph.getEp linkName linkObj peerNodeName;
      };
    in
    helpers.addRoutesOnLink node linkName routes.routes4 routes.routes6;

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
      addDefaultsTowardPeer {
        inherit
          links
          linkName
          mkRoute4
          mkRoute6
          ;
        node = acc;
        peerNodeName = policyNodeName;
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
        node = acc;
        peerNodeName = selectorNodeName;
      }
    ) node laneLinks;
}
