{ lib, self ? { outPath = ./.; }, ... }:

let
  link = import (self.outPath + "/implementation/lib/topology/link-utils.nix") { inherit lib self; };
  helpers = import ./static-helpers.nix { inherit lib self; };
  routeBuilder = import ./lane-default-route-builder.nix { inherit lib self; };
  laneMetadata = import ./lane-metadata.nix { inherit lib self; };
  upstreamSelectorLaneDefaults = import ./upstream-selector-lane-defaults.nix { inherit lib self; };
  inherit (routeBuilder) addDefaultsTowardPeer;
  inherit (laneMetadata)
    defaultMetricForLane
    hasUplinkLane
    laneAccessNodeName
    laneUplinkName
    ;

  uplinkHasDefault =
    routeFacts: uplinkName:
    builtins.hasAttr uplinkName (routeFacts.uplinkHasDefaultSet or { });

in
{
  addDownstreamSelectorPolicyDefaults =
    {
      topo,
      nodeName,
      node,
      routeContext,
      routeFacts ? routeContext.buildFacts topo,
    }:
    let
      inherit (routeContext) mkRoute4 mkRoute6;

      policyNodeName = topo.policyNodeName or null;
      links = topo.links or { };
      role = node.role or null;
      uplinksForAccess =
        accessName:
        lib.unique (
          lib.filter (uplinkName: uplinkName != null) (
            map (linkName: laneUplinkName links.${linkName}) (
              lib.filter (
                linkName:
                let
                  linkObj = links.${linkName};
                  members = link.membersOf linkObj;
                in
                lib.elem policyNodeName members
                && lib.elem (topo.upstreamSelectorNodeName or null) members
                && laneAccessNodeName linkObj == accessName
                && hasUplinkLane linkObj
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
              members = link.membersOf linkObj;
            in
            lib.elem nodeName members
            && lib.elem policyNodeName members
            && laneAccessNodeName linkObj != null
          ) (lib.sort (a: b: a < b) (builtins.attrNames links));
    in
    builtins.foldl' (
      acc: linkName:
      let
        linkObj = links.${linkName};
        accessName = laneAccessNodeName linkObj;
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
        policyOnly = true;
        reason = "policy-derived-default";
      }
    ) node laneLinks;

  addPolicyUpstreamSelectorDefaults =
    {
      topo,
      nodeName,
      node,
      routeContext,
      routeFacts ? routeContext.buildFacts topo,
    }:
    let
      inherit (routeContext) mkRoute4 mkRoute6;

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
              members = link.membersOf linkObj;
            in
            lib.elem policyNodeName members
            && lib.elem selectorNodeName members
            && laneAccessNodeName linkObj != null
            && hasUplinkLane linkObj
          ) (lib.sort (a: b: a < b) (builtins.attrNames links));
    in
    builtins.foldl' (
      acc: linkName:
      let
        uplinkName = laneUplinkName links.${linkName};
      in
      if uplinkName == null || !(uplinkHasDefault routeFacts uplinkName) then
        acc
      else
        addDefaultsTowardPeer {
          inherit
            links
            linkName
            mkRoute4
            mkRoute6
            ;
          lane = {
            access = laneAccessNodeName links.${linkName};
            uplink = uplinkName;
          };
          metric = defaultMetricForLane topo links.${linkName};
          node = acc;
          peerNodeName = selectorNodeName;
          policyOnly = true;
          reason = "policy-derived-default";
        }
    ) node laneLinks;

  addUpstreamSelectorPolicyLaneCoreDefaults =
    upstreamSelectorLaneDefaults.addPolicyLaneCoreDefaults;
}
