{ lib, self ? { outPath = ./.; }, ... }:

let
  link = import (self.outPath + "/implementation/lib/topology/link-utils.nix") { inherit lib self; };
  helpers = import ./static-helpers.nix { inherit lib self; };
  defaultRoutePolicy = import ./default-route-policy.nix { inherit lib; };
  routeBuilder = import ./lane-default-route-builder.nix { inherit lib self; };
  laneMetadata = import ./lane-metadata.nix { inherit lib self; };
  upstreamSelectorLaneDefaults = import ./upstream-selector-lane-defaults.nix { inherit lib self; };
  inherit (routeBuilder) mkDefaultRoutes;
  inherit (laneMetadata)
    defaultMetricForLane
    hasUplinkLane
    laneAccessNodeName
    laneUplinkName
    ;

  uplinkHasDefault =
    routeFacts: uplinkName:
    builtins.hasAttr uplinkName (routeFacts.uplinkHasDefaultSet or { });

  uplinkHasExecutableDefault =
    routeFacts: uplinkName:
    uplinkHasDefault routeFacts uplinkName
    || builtins.hasAttr uplinkName (routeFacts.overlayUplinkNameSet or { });

in
rec {
  downstreamSelectorPolicyDefaultPlan =
    { topo
    , nodeName
    , node
    , routeContext
    , routeFacts ? routeContext.buildFacts topo
    ,
    }:
    let
      inherit (routeContext) mkRoute4 mkRoute6;

      policyNodeName = topo.policyNodeName or null;
      links = topo.links or { };
      role = node.role or null;
      uplinksForAccess = defaultRoutePolicy.anyTrafficDefaultUplinksForAccess topo;
      laneLinks =
        if role != "downstream-selector" || policyNodeName == null then
          [ ]
        else
          lib.filter
            (
              linkName:
              let
                linkObj = links.${linkName};
                members = link.membersOf linkObj;
              in
              lib.elem nodeName members
              && lib.elem policyNodeName members
              && laneAccessNodeName linkObj != null
            )
            (lib.sort (a: b: a < b) (builtins.attrNames links));
    in
    builtins.foldl'
      (
        acc: linkName:
        let
          linkObj = links.${linkName};
          accessName = laneAccessNodeName linkObj;
          uplinks = uplinksForAccess accessName;
          uplinkName = if uplinks == [ ] then null else builtins.head (lib.sort (a: b: a < b) uplinks);
          routes = mkDefaultRoutes {
            inherit
              mkRoute4
              mkRoute6
              ;
            epTo = link.getEp linkName linkObj policyNodeName;
            lane = {
              access = accessName;
              uplink = uplinkName;
            };
            policyOnly = true;
            reason = "policy-derived-default";
            relationIds =
              if uplinkName != null then
                defaultRoutePolicy.relationIdsForAccessUplink topo accessName uplinkName
              else null;
            direction = "outbound";
            returnBehavior =
              if uplinkName != null then
                defaultRoutePolicy.returnBehaviorForAccessUplink topo accessName uplinkName
              else null;
          };
        in
        acc
        // {
          "${linkName}" = {
            routes4 = (acc.${linkName}.routes4 or [ ]) ++ routes.routes4;
            routes6 = (acc.${linkName}.routes6 or [ ]) ++ routes.routes6;
          };
        }
      )
      { }
      laneLinks;

  addDownstreamSelectorPolicyDefaults =
    args: helpers.addRoutePlan args.node (downstreamSelectorPolicyDefaultPlan args);

  policyUpstreamSelectorDefaultPlan =
    { topo
    , nodeName
    , node
    , routeContext
    , routeFacts ? routeContext.buildFacts topo
    ,
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
          lib.filter
            (
              linkName:
              let
                linkObj = links.${linkName};
                members = link.membersOf linkObj;
              in
              lib.elem policyNodeName members
              && lib.elem selectorNodeName members
              && laneAccessNodeName linkObj != null
              && hasUplinkLane linkObj
            )
            (lib.sort (a: b: a < b) (builtins.attrNames links));
    in
    builtins.foldl'
      (
        acc: linkName:
        let
          uplinkName = laneUplinkName links.${linkName};
        in
        if
          uplinkName == null
          || !(uplinkHasExecutableDefault routeFacts uplinkName)
          || !(defaultRoutePolicy.accessMayUseDefault topo (laneAccessNodeName links.${linkName}) uplinkName)
        then
          acc
        else
          let
            linkObj = links.${linkName};
            routes = mkDefaultRoutes {
              inherit
                mkRoute4
                mkRoute6
                ;
              epTo = link.getEp linkName linkObj selectorNodeName;
              lane = {
                access = laneAccessNodeName linkObj;
                uplink = uplinkName;
              };
              metric = defaultMetricForLane topo linkObj;
              policyOnly = true;
              reason = "policy-derived-default";
              relationIds = defaultRoutePolicy.relationIdsForAccessUplink topo (laneAccessNodeName linkObj) uplinkName;
              direction = "outbound";
              returnBehavior = defaultRoutePolicy.returnBehaviorForAccessUplink topo (laneAccessNodeName linkObj) uplinkName;
            };
          in
          acc
          // {
            "${linkName}" = {
              routes4 = (acc.${linkName}.routes4 or [ ]) ++ routes.routes4;
              routes6 = (acc.${linkName}.routes6 or [ ]) ++ routes.routes6;
            };
          }
      )
      { }
      laneLinks;

  addPolicyUpstreamSelectorDefaults =
    args: helpers.addRoutePlan args.node (policyUpstreamSelectorDefaultPlan args);

  inherit (upstreamSelectorLaneDefaults)
    addPolicyLaneCoreDefaults
    policyLaneCoreDefaultPlan
    ;

  addUpstreamSelectorPolicyLaneCoreDefaults = upstreamSelectorLaneDefaults.addPolicyLaneCoreDefaults;
}
