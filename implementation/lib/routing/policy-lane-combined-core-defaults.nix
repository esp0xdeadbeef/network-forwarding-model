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
  selectorCoreLink = import ./selector-core-link.nix { inherit lib self; };
  inherit (routeBuilder) mkMultipathDefaultRoutes;
  inherit (laneMetadata)
    defaultMetricForUplinks
    laneAccessNodeName
    laneMeta
    laneScopeName
    laneUplinkName
    ;
  inherit (selectorCoreLink)
    coreEpForUplink
    ;
in
rec {
  # The upstream-selector is the role that owns the multi-WAN choice, so it
  # emits one ECMP default across the permitted cores for every multi-uplink
  # access unit. The access unit's policy->upstream-selector lanes are emitted
  # one per permitted uplink (FS-370-SMS-050 requires a non-null lane.uplink on
  # every access-uplink lane), so the multi-uplink group is the set of those
  # per-uplink lanes that share one access unit, not a single uplink-less lane.
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

      accessUplinkLanes =
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
            && laneScopeName linkObj != null
            && (meta.kind or null) == "access-uplink"
            && (meta.uplink or null) != null
          ) linkNames;

      # FS-171/FS-481: group the per-exit lanes by their **source scope** (the
      # tenant), not the access node. A scope with two or more distinct permitted
      # exits has a multi-exit selection that owns one ECMP default on the
      # selector; a single-exit scope keeps its ordinary per-exit default route.
      lanesByScope = builtins.foldl' (
        acc: laneLinkName:
        let
          scope = laneScopeName links.${laneLinkName};
          key = toString scope;
        in
        acc // { ${key} = (acc.${key} or [ ]) ++ [ laneLinkName ]; }
      ) { } accessUplinkLanes;

      scopeUplinks =
        scope: scopeGroup:
        lib.sort (a: b: a < b) (
          lib.unique (
            builtins.filter (u: u != null) (
              map (laneLinkName: (laneMeta links.${laneLinkName}).uplink or null) scopeGroup
            )
          )
        );
    in
    builtins.foldl'
      (
        acc: accessUplinkEntry:
        let
          access = accessUplinkEntry.scope;
          uplinks = accessUplinkEntry.uplinks;
          group = accessUplinkEntry.group;
          linkAndPolicyEligible =
            uplinkName:
            selectorCoreLink.coreLinkForUplink topo selectorNodeName uplinkName != null
            && defaultRoutePolicy.accessMayUseDefault topo access uplinkName;
          coreEntry =
            familyFlag: uplinkName:
            if !(linkAndPolicyEligible uplinkName) then
              null
            else if !(familyFlag routeFacts uplinkName) then
              null
            else
              {
                inherit uplinkName;
                epTo = coreEpForUplink topo selectorNodeName uplinkName;
              };
          # Per-family member sets (FS-315, SMS-010): a route selection key carries
          # one address family, so an egress joins a family's multipath group only
          # when it offers a default for THAT family. An uplink with an IPv4
          # default and no IPv6 default stays out of the IPv6 member set instead
          # of producing an IPv6 nexthop with no route behind it.
          coreEntriesFor =
            familyFlag:
            builtins.filter (entry: entry != null && entry.epTo != null) (map (coreEntry familyFlag) uplinks);
          coreEntries4 = coreEntriesFor selectorCoreLink.uplinkHasExecutableDefault4;
          coreEntries6 = coreEntriesFor selectorCoreLink.uplinkHasExecutableDefault6;
          relationIds = lib.unique (
            builtins.concatMap (
              entry: defaultRoutePolicy.relationIdsForAccessUplink topo access entry.uplinkName
            ) (coreEntries4 ++ coreEntries6)
          );
          # FS-481: the upstream-selector owns the ECMP member set across the
          # scope's selected exits. The same member set is installed on every
          # policy<->selector lane of the scope, because the policy point picks
          # one of the scope's lanes and every lane must reach every selected
          # exit. This is the selector's own selection authority, not a route
          # copied into an unrelated sibling lane (FS-315).
          routes =
            if coreEntries4 == [ ] && coreEntries6 == [ ] then
              {
                routes4 = [ ];
                routes6 = [ ];
              }
            else
              mkMultipathDefaultRoutes {
                inherit mkRoute4 mkRoute6;
                epsTo4 = map (entry: entry.epTo) coreEntries4;
                epsTo6 = map (entry: entry.epTo) coreEntries6;
                multipathAuthority = "${toString access}-default";
                lane = {
                  access = toString access;
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
        builtins.foldl' (
          inner: laneLinkName:
          inner
          // {
            "${laneLinkName}" = {
              routes4 = (inner.${laneLinkName}.routes4 or [ ]) ++ routes.routes4;
              routes6 = (inner.${laneLinkName}.routes6 or [ ]) ++ routes.routes6;
            };
          }
        ) acc group
      )
      { }
      (
        builtins.concatLists (
          lib.mapAttrsToList (
            access: group:
            let
              uplinks = scopeUplinks access group;
            in
            if builtins.length uplinks <= 1 then
              [ ]
            else
              [
                {
                  scope = access;
                  inherit group uplinks;
                }
              ]
          ) lanesByScope
        )
      );

  addPolicyLaneCombinedCoreDefaults =
    args: helpers.addRoutePlan args.node (policyLaneCombinedCoreDefaultPlan args);
}
