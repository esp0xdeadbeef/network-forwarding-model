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
  inherit (laneMetadata)
    defaultMetricForUplinks
    laneAccessNodeName
    laneMeta
    ;
in
rec {
  # A multi-uplink access unit keeps a single policy->upstream-selector lane.
  # The policy point emits ONE default toward the upstream-selector; the
  # upstream-selector owns the ECMP across the permitted cores.
  policyUpstreamSelectorCombinedDefaultPlan =
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
              meta = laneMeta linkObj;
            in
            lib.elem policyNodeName members
            && lib.elem selectorNodeName members
            && laneAccessNodeName linkObj != null
            && (meta.kind or null) == "access-uplink"
            && (meta.uplink or null) == null
          ) (lib.sort (a: b: a < b) (builtins.attrNames links));
    in
    builtins.foldl' (
      acc: linkName:
      let
        linkObj = links.${linkName};
        access = laneAccessNodeName linkObj;
        uplinks = lib.sort (a: b: a < b) ((laneMeta linkObj).uplinks or [ ]);
        relationIds = lib.unique (
          builtins.concatMap (
            uplinkName: defaultRoutePolicy.relationIdsForAccessUplink topo access uplinkName
          ) uplinks
        );
        routes = mkDefaultRoutes {
          inherit
            mkRoute4
            mkRoute6
            ;
          epTo = link.getEp linkName linkObj selectorNodeName;
          lane = {
            inherit access;
            uplink = null;
            inherit uplinks;
          };
          metric = defaultMetricForUplinks topo uplinks;
          policyOnly = true;
          reason = "policy-derived-default";
          inherit relationIds;
          direction = "outbound";
          returnBehavior = "symmetric";
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

  addPolicyUpstreamSelectorCombinedDefaults =
    args: helpers.addRoutePlan args.node (policyUpstreamSelectorCombinedDefaultPlan args);
}
