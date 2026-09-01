{
  lib,
  self ? {
    outPath = ./.;
  },
  ...
}:

let
  link = import (self.outPath + "/implementation/lib/topology/link-utils.nix") { inherit lib self; };
  helpers = import ./static-helpers.nix { inherit lib self; };
  defaultRoutePolicy = import ./default-route-policy.nix { inherit lib; };
  routeBuilder = import ./lane-default-route-builder.nix { inherit lib self; };
  laneMetadata = import ./lane-metadata.nix { inherit lib self; };
  inherit (routeBuilder) mkDefaultRoutes;
  inherit (laneMetadata) laneAccessNodeName;
in
rec {
  downstreamSelectorPolicyDefaultPlan =
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
      uplinksForAccess = defaultRoutePolicy.anyTrafficDefaultUplinksForAccess topo;
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
            lib.elem nodeName members && lib.elem policyNodeName members && laneAccessNodeName linkObj != null
          ) (lib.sort (a: b: a < b) (builtins.attrNames links));
    in
    builtins.foldl' (
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
            else
              null;
          direction = "outbound";
          returnBehavior =
            if uplinkName != null then
              defaultRoutePolicy.returnBehaviorForAccessUplink topo accessName uplinkName
            else
              null;
        };
      in
      acc
      // {
        "${linkName}" = {
          routes4 = (acc.${linkName}.routes4 or [ ]) ++ routes.routes4;
          routes6 = (acc.${linkName}.routes6 or [ ]) ++ routes.routes6;
        };
      }
    ) { } laneLinks;

  addDownstreamSelectorPolicyDefaults =
    args: helpers.addRoutePlan args.node (downstreamSelectorPolicyDefaultPlan args);
}
