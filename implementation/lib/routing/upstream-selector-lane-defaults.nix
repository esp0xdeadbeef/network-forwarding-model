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
  inherit (routeBuilder) mkDefaultRoutes mkMultipathDefaultRoutes;
  inherit (laneMetadata)
    defaultMetricForLane
    defaultMetricForUplinks
    hasUplinkLane
    laneAccessNodeName
    laneMeta
    laneUplinkName
    ;
in
rec {
  policyLaneCoreDefaultPlan =
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
      uplinkHasDefault = uplinkName: builtins.hasAttr uplinkName (routeFacts.uplinkHasDefaultSet or { });
      uplinkHasExecutableDefault =
        uplinkName:
        uplinkHasDefault uplinkName || builtins.hasAttr uplinkName (routeFacts.overlayUplinkNameSet or { });

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
          matches = lib.filter (
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
      perCoreLink = builtins.foldl' (
        acc: policyLinkName:
        let
          policyLink = links.${policyLinkName};
          uplinkName = laneUplinkName policyLink;
          coreLinkName = coreLinkForUplink uplinkName;
          targetLinkName = if coreLinkName == null then policyLinkName else coreLinkName;
          routes =
            if
              coreLinkName == null
              || uplinkName == null
              || !(uplinkHasExecutableDefault uplinkName)
              || !(defaultRoutePolicy.accessMayUseDefault topo (laneAccessNodeName policyLink) uplinkName)
            then
              {
                routes4 = [ ];
                routes6 = [ ];
              }
            else
              mkDefaultRoutes {
                inherit mkRoute4 mkRoute6;
                epTo = link.getEp coreLinkName links.${coreLinkName} (
                  builtins.head (
                    lib.filter (memberName: memberName != selectorNodeName) (link.membersOf links.${coreLinkName})
                  )
                );
                lane = {
                  access = laneAccessNodeName policyLink;
                  uplink = uplinkName;
                };
                metric = defaultMetricForLane topo policyLink;
                policyOnly = true;
                reason = "policy-derived-default";
                relationIds =
                  defaultRoutePolicy.relationIdsForAccessUplink topo (laneAccessNodeName policyLink)
                    uplinkName;
                direction = "outbound";
                returnBehavior =
                  defaultRoutePolicy.returnBehaviorForAccessUplink topo (laneAccessNodeName policyLink)
                    uplinkName;
              };
        in
        acc
        // {
          "${targetLinkName}" = {
            routes4 = (acc.${targetLinkName}.routes4 or [ ]) ++ routes.routes4;
            routes6 = (acc.${targetLinkName}.routes6 or [ ]) ++ routes.routes6;
          };
        }
      ) { } policyLaneLinks;
    in
    perCoreLink;

  addPolicyLaneCoreDefaults = args: helpers.addRoutePlan args.node (policyLaneCoreDefaultPlan args);

  # Multi-uplink access units keep one policy->upstream-selector lane; the
  # upstream-selector is the role that owns the multi-WAN choice, so it emits
  # one ECMP default across the permitted cores for that lane.
  policyLaneCombinedCoreDefaultPlan =
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
      uplinkHasDefault = uplinkName: builtins.hasAttr uplinkName (routeFacts.uplinkHasDefaultSet or { });
      uplinkHasExecutableDefault =
        uplinkName:
        uplinkHasDefault uplinkName || builtins.hasAttr uplinkName (routeFacts.overlayUplinkNameSet or { });

      combinedLaneLinks =
        if role != "upstream-selector" || selectorNodeName != nodeName || policyNodeName == null then
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
          ) linkNames;

      coreLinkForUplink =
        uplinkName:
        let
          matches = lib.filter (
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
      acc: laneLinkName:
      let
        laneLink = links.${laneLinkName};
        access = laneAccessNodeName laneLink;
        uplinks = lib.sort (a: b: a < b) ((laneMeta laneLink).uplinks or [ ]);
        coreEntries = builtins.filter (entry: entry != null && entry.epTo != null) (
          map (
            uplinkName:
            let
              coreLinkName = coreLinkForUplink uplinkName;
            in
            if
              coreLinkName == null
              || !(uplinkHasExecutableDefault uplinkName)
              || !(defaultRoutePolicy.accessMayUseDefault topo access uplinkName)
            then
              null
            else
              {
                inherit uplinkName;
                epTo = link.getEp coreLinkName links.${coreLinkName} (
                  builtins.head (
                    lib.filter (memberName: memberName != selectorNodeName) (link.membersOf links.${coreLinkName})
                  )
                );
              }
          ) uplinks
        );
        relationIds = lib.unique (
          builtins.concatMap (
            entry: defaultRoutePolicy.relationIdsForAccessUplink topo access entry.uplinkName
          ) coreEntries
        );
        routes =
          if builtins.length coreEntries <= 1 then
            {
              routes4 = [ ];
              routes6 = [ ];
            }
          else
            mkMultipathDefaultRoutes {
              inherit mkRoute4 mkRoute6;
              epsTo = map (entry: entry.epTo) coreEntries;
              multipathAuthority = "${access}-default";
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
        "${laneLinkName}" = {
          routes4 = (acc.${laneLinkName}.routes4 or [ ]) ++ routes.routes4;
          routes6 = (acc.${laneLinkName}.routes6 or [ ]) ++ routes.routes6;
        };
      }
    ) { } combinedLaneLinks;

  addPolicyLaneCombinedCoreDefaults =
    args: helpers.addRoutePlan args.node (policyLaneCombinedCoreDefaultPlan args);
}
