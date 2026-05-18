{ lib, self ? { outPath = ./.; }, ... }:

let
  link = import (self.outPath + "/lib/topology/link-utils.nix") { inherit lib self; };
  helpers = import ./static-helpers.nix { inherit lib self; };
  routeBuilder = import ./lane-default-route-builder.nix { inherit lib self; };
  laneMetadata = import ./lane-metadata.nix { inherit lib self; };
  inherit (routeBuilder) mkDefaultRoutes;
  inherit (laneMetadata)
    defaultMetricForLane
    hasUplinkLane
    laneAccessNodeName
    laneUplinkName
    ;
in
{
  addPolicyLaneCoreDefaults =
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

      linkNames = lib.sort (a: b: a < b) (builtins.attrNames links);
      uplinkHasDefault =
        uplinkName:
        builtins.hasAttr uplinkName (routeFacts.uplinkHasDefaultSet or { });

      policyLaneLinks =
        if role != "upstream-selector" || selectorNodeName != nodeName || policyNodeName == null then
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
          ) linkNames;

      coreLinkForUplink =
        uplinkName:
        let
          matches =
            lib.filter (
              linkName:
              let
                linkObj = links.${linkName};
                members = link.membersOf linkObj;
              in
              lib.elem selectorNodeName members
              && laneAccessNodeName linkObj == null
              && laneUplinkName linkObj == uplinkName
              && lib.any (memberName: ((topo.nodes or { }).${memberName} or { }).role or null == "core") members
            ) linkNames;
        in
        if matches == [ ] then null else builtins.head matches;
    in
    builtins.foldl' (
      acc: policyLinkName:
      let
        policyLink = links.${policyLinkName};
        uplinkName = laneUplinkName policyLink;
        coreLinkName = coreLinkForUplink uplinkName;
        routes =
          if coreLinkName == null || uplinkName == null || !(uplinkHasDefault uplinkName) then
            { routes4 = [ ]; routes6 = [ ]; }
          else
            mkDefaultRoutes {
              inherit mkRoute4 mkRoute6;
              epTo = link.getEp coreLinkName links.${coreLinkName} (
                builtins.head (
                  lib.filter
                    (memberName: memberName != selectorNodeName)
                    (link.membersOf links.${coreLinkName})
                )
              );
              lane = {
                access = laneAccessNodeName policyLink;
                uplink = uplinkName;
              };
              metric = defaultMetricForLane topo policyLink;
              policyOnly = true;
              reason = "policy-derived-default";
            };
      in
      helpers.addRoutesOnLink acc (if coreLinkName == null then policyLinkName else coreLinkName) routes.routes4 routes.routes6
    ) node policyLaneLinks;
}
