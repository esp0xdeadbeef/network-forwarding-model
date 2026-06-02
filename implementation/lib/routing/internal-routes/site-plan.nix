{ lib, self ? { outPath = ./.; }, ... }:

let
  graphContext = import (self.outPath + "/implementation/lib/routing/graph/context.nix") { inherit lib self; };
  helpers = import (self.outPath + "/implementation/lib/routing/static-helpers.nix") { inherit lib self; };
  link = import (self.outPath + "/implementation/lib/topology/link-utils.nix") { inherit lib self; };
  trace = import (self.outPath + "/lib/trace.nix") { };
  remotePrefixes = import (self.outPath + "/implementation/lib/routing/internal-routes/remote-prefixes.nix") {
    inherit lib self;
  };
  routeGroups = import (self.outPath + "/implementation/lib/routing/internal-routes/route-groups.nix") {
    inherit lib self;
  };
  routeCandidates = import (self.outPath + "/implementation/lib/routing/internal-routes/route-candidates.nix");

  sum = xs: builtins.foldl' (acc: x: acc + x) 0 xs;

  countRemoteByKind =
    remoteByNode: kind:
    sum (map (nodeFacts: builtins.length (nodeFacts.${kind} or [ ])) (builtins.attrValues remoteByNode));

  groupValues = keyFn: xs: builtins.groupBy keyFn xs;

in
{
  build =
    { topo
    , routeContext
    , routeFacts ? routeContext.buildFacts topo
    , remotePrefixFacts ? remotePrefixes.buildFacts topo
    , routeGraph ? graphContext.build (topo.links or { }) { }
    , realRouteGraph ? graphContext.build (topo.links or { }) {
        nodeNames = builtins.attrNames (topo.nodes or { });
      }
    ,
    }:
    let
      inherit (routeContext)
        loopbackOwnerNodeForDstWithFacts
        mkRoute4
        mkRoute6
        nextHopWithPreferredUplinks
        ;
      mode = helpers.aggregationMode topo;
      links = topo.links or { };
      nodes = topo.nodes or { };
      nodeNames = builtins.attrNames (topo.nodes or { });
      includeP2p = builtins.getEnv "S88_NFM_PROFILE_SKIP_INTERNAL_P2P" != "1";
      includeTenant = builtins.getEnv "S88_NFM_PROFILE_SKIP_INTERNAL_TENANT" != "1";
      includeOverlay = builtins.getEnv "S88_NFM_PROFILE_SKIP_INTERNAL_OVERLAY" != "1";

      tenantReachableFromNode =
        nodeName: entry:
        let
          node = nodes.${nodeName} or { };
          nodeRole = node.role or null;
          uplinksOnNode = remotePrefixFacts.uplinksByNode.${nodeName} or [ ];
          allowedUplinks = remotePrefixFacts.uplinksByAccess.${entry.owner} or [ ];
        in
        nodeRole != "core"
        || uplinksOnNode == [ ]
        || builtins.any (uplinkName: builtins.elem uplinkName allowedUplinks) uplinksOnNode;

      overlayAllowedOnNode =
        nodeName: entry:
        let
          node = nodes.${nodeName} or { };
          nodeRole = node.role or null;
          uplinksOnNode = remotePrefixFacts.uplinksByNode.${nodeName} or [ ];
          overlayName = entry.overlay or null;
          policyScoped = overlayName != null && builtins.hasAttr overlayName remotePrefixFacts.overlayPolicyAllowedNodes;
          attachmentScoped = overlayName != null && builtins.hasAttr overlayName remotePrefixFacts.overlayAllowedNodes;
          isNonOverlayUplinkCore =
            nodeRole == "core"
            && overlayName != null
            && builtins.any (uplinkName: uplinkName != overlayName) uplinksOnNode;
        in
        if isNonOverlayUplinkCore then
          true
        else if policyScoped then
          builtins.elem nodeName remotePrefixFacts.overlayPolicyAllowedNodes.${overlayName}
        else if attachmentScoped then
          builtins.elem nodeName remotePrefixFacts.overlayAllowedNodes.${overlayName}
        else
          true;

      sourceEligibleForEntry =
        nodeName: entry:
        let
          node = nodes.${nodeName} or { };
          nodeRole = node.role or null;
          ownSet = remotePrefixFacts.ownConnectedPrefixSetByNode.${nodeName} or { };
          ownsDst =
            if entry ? dst then
              ownSet ? "${toString entry.family}|${entry.dst}"
            else
              false;
        in
        entry.owner != nodeName
        && !ownsDst
        && (
          if entry.kind == "tenant" || entry.kind == "runtime-routed-prefix" then
            tenantReachableFromNode nodeName entry
            && !((entry.kind or null) == "runtime-routed-prefix" && nodeRole == "access")
          else if entry.kind == "overlay" then
            overlayAllowedOnNode nodeName entry
          else
            true
        );

      entriesByKind =
        (if includeP2p then remotePrefixFacts.p2pEntries else [ ])
        ++ (if includeTenant then
          map
            (
              entry:
              ({
                family = entry.family;
                owner = entry.owner;
                kind = entry.kind or "tenant";
              }
              // lib.optionalAttrs (entry ? dst) { dst = entry.dst; }
              // lib.optionalAttrs (entry ? sourceFile) {
                sourceFile = entry.sourceFile;
                prefixName = entry.prefixName or null;
                delegatedPrefixLength = entry.delegatedPrefixLength or null;
                perTenantPrefixLength = entry.perTenantPrefixLength or null;
                slot = entry.slot or null;
              }
              // lib.optionalAttrs ((entry.prefixPostfix or null) != null) { prefixPostfix = entry.prefixPostfix; })
            )
            (remotePrefixFacts.tenantOwnerEntries or [ ])
        else [ ])
        ++ (if includeOverlay then remotePrefixFacts.overlayRouteEntries else [ ]);

      rowsForEntry =
        entry:
        let
          eligibleNodeNames = builtins.filter (nodeName: sourceEligibleForEntry nodeName entry) nodeNames;
          baseRows =
            map
              (nodeName: {
                inherit nodeName entry;
              })
              eligibleNodeNames;
          serviceScopes =
            if (entry.kind or null) == "tenant" then
              remotePrefixFacts.serviceRouteScopesByOwner.${entry.owner} or [ ]
            else
              [ ];
          scopedRows =
            lib.concatMap
              (
                scope:
                  map
                    (nodeName: {
                      inherit nodeName;
                      entry = entry // { routeScope = scope; };
                    })
                    eligibleNodeNames
              )
              serviceScopes;
        in
        baseRows ++ scopedRows;

      sourceRows = lib.concatMap rowsForEntry entriesByKind;

      resolutionKey =
        row:
        let
          e = row.entry;
          routeScope = e.routeScope or { };
        in
        "${row.nodeName}|${toString (e.owner or "")}|${toString (e.kind or "")}|${toString (e.overlay or "")}|${toString (e.peerSite or "")}|${toString (routeScope.access or "")}|${toString (routeScope.uplink or "")}|${toString (routeScope.serviceName or "")}";

      remoteGroups = groupValues resolutionKey sourceRows;

      resolveGroup =
        row:
        let
          nodeName = row.nodeName;
          dstEntry = row.entry;
          routeScope = dstEntry.routeScope or null;

          primaryPath = routeGraph.shortestPath {
            src = nodeName;
            dst = dstEntry.owner;
          };

          firstHopHasRealLink =
            path:
            if path == null || builtins.length path < 2 then
              false
            else
              routeGraph.linksBetween nodeName (builtins.elemAt path 1) != [ ];

          selectedRouteGraph = if firstHopHasRealLink primaryPath then routeGraph else realRouteGraph;

          path = selectedRouteGraph.shortestPath {
            src = nodeName;
            dst = dstEntry.owner;
          };
        in
        if path == null || builtins.length path < 2 then
          [ ]
        else
          let
            hop = builtins.elemAt path 1;
            uplinksForCore =
              coreName:
              lib.filter
                (
                  uplinkName:
                  builtins.elem coreName (routeFacts.uplinkCoreNamesByUplink.${uplinkName} or [ ])
                )
                (builtins.attrNames (routeFacts.uplinkCoreNamesByUplink or { }));
            preferredUplinks =
              if routeScope != null && (routeScope.uplink or null) != null then
                [ routeScope.uplink ]
              else if dstEntry.kind == "overlay" && (dstEntry.overlay or null) != null then
                [ dstEntry.overlay ]
              else if dstEntry.kind == "p2p" && builtins.hasAttr (dstEntry.owner or "") (routeFacts.uplinkCoreSet or { }) then
                uplinksForCore dstEntry.owner
              else if builtins.hasAttr (dstEntry.owner or "") (routeFacts.uplinkCoreSet or { }) then
                topo.uplinkNames or [ ]
              else
                [ ];
            overlayAllowedAccessNodes =
              if dstEntry.kind == "overlay" && (dstEntry.overlay or null) != null then
                builtins.attrNames (
                  lib.filterAttrs
                    (_: uplinks: builtins.elem dstEntry.overlay uplinks)
                    (remotePrefixFacts.uplinksByAccess or { })
                )
              else
                [ ];
            preferredAccessNodes = lib.unique (
              if routeScope != null && (routeScope.access or null) != null then
                [ routeScope.access ]
              else
                lib.filter (x: x != null) [
                  (dstEntry.owner or null)
                  (if dstEntry ? dst then loopbackOwnerNodeForDstWithFacts routeFacts dstEntry.family dstEntry.dst else null)
                ]
              ++ overlayAllowedAccessNodes
            );
            baseNh = nextHopWithPreferredUplinks {
              inherit topo;
              from = nodeName;
              to = hop;
              routeGraph = selectedRouteGraph;
              inherit preferredUplinks preferredAccessNodes;
            };
            candidateLinks = routeCandidates {
              inherit
                link
                lib
                nodeName
                preferredUplinks
                routeContext
                topo
                ;
              inherit preferredAccessNodes;
              routeGraph = selectedRouteGraph;
              baseLinkName = baseNh.linkName;
              isOverlay = dstEntry.kind == "overlay";
              isP2p = dstEntry.kind == "p2p";
              hopNode = hop;
              preferScopedLane = routeScope != null;
            };
          in
          builtins.filter (entry: entry != null) (
            map
              (
                linkName:
                let
                  linkObj = links.${linkName};
                  epTo = link.getEp linkName linkObj hop;
                  via4 = if epTo ? addr4 && epTo.addr4 != null then helpers.stripMask epTo.addr4 else null;
                  via6 = if epTo ? addr6 && epTo.addr6 != null then helpers.stripMask epTo.addr6 else null;
                in
                if linkName == null then
                  null
                else if dstEntry.family == 4 && via4 == null then
                  null
                else if dstEntry.family == 6 && via6 == null then
                  null
                else
                  {
                    inherit nodeName linkName via4 via6;
                  }
              )
              candidateLinks
          );

      resolveGroupRows =
        rows:
        let
          sampleRow = builtins.head rows;
          resolvedHops = resolveGroup sampleRow;
          buildRowsForHop =
            resolvedHop:
            map
              (row: row.entry // resolvedHop)
              rows;
        in
        lib.concatMap buildRowsForHop resolvedHops;

      resolvedRows = lib.concatMap
        (key: resolveGroupRows remoteGroups.${key})
        (builtins.attrNames remoteGroups);

      perNextHopKey =
        e:
        let
          routeScope = e.routeScope or { };
        in
        "${e.nodeName}|${e.linkName}|${toString e.family}|${toString (e.via4 or "")}|${toString (e.via6 or "")}|${e.kind}|${toString (e.overlay or "")}|${toString (e.peerSite or "")}|${toString (e.sourceFile or "")}|${toString (routeScope.access or "")}|${toString (routeScope.uplink or "")}|${toString (routeScope.serviceName or "")}";

      nextHopGroups = groupValues perNextHopKey resolvedRows;

      buildRouteRow =
        rows:
        let
          sample = builtins.head rows;
          built = routeGroups.build {
            entries = rows;
            inherit
              mkRoute4
              mkRoute6
              mode
              topo
              ;
            linkName = sample.linkName;
            via4 = sample.via4;
            via6 = sample.via6;
          };
        in
        {
          inherit (sample) nodeName;
          inherit (built) linkName routes4 routes6;
        };

      routeRows = map
        (key: buildRouteRow nextHopGroups.${key})
        (builtins.attrNames nextHopGroups);

      byNodeLink = groupValues (row: "${row.nodeName}\n${row.linkName}") routeRows;
      linksByNode = groupValues (row: row.nodeName) routeRows;

      buildNodePlan =
        nodeName:
        let
          nodeRows = linksByNode.${nodeName} or [ ];
          linkNames = builtins.attrNames (groupValues (row: row.linkName) nodeRows);
        in
        builtins.listToAttrs (
          map
            (
              linkName:
              let
                rows = byNodeLink."${nodeName}\n${linkName}" or [ ];
              in
              {
                name = linkName;
                value = {
                  plannedRoutesNormalized = true;
                  routes4 = lib.concatMap (row: row.routes4 or [ ]) rows;
                  routes6 = lib.concatMap (row: row.routes6 or [ ]) rows;
                };
              }
            )
            linkNames
        );

      byNode = builtins.listToAttrs (
        map
          (nodeName: {
            name = nodeName;
            value = buildNodePlan nodeName;
          })
          nodeNames
      );

      remoteByNode = remotePrefixFacts.remoteByNode or { };
      diagnostics = {
        planner = "scratch-site-wide";
        usesExistingPerNodeExpansion = false;
        routeAtoms = {
          tenant = builtins.length (remotePrefixFacts.tenantOwnerEntries or [ ]);
          overlay = builtins.length (remotePrefixFacts.overlayRouteEntries or [ ]);
          p2p = builtins.length (remotePrefixFacts.p2pEntries or [ ]);
        };
        sourceEligibilityPairs = {
          tenant = countRemoteByKind remoteByNode "tenant";
          overlay = countRemoteByKind remoteByNode "overlay";
          p2p = countRemoteByKind remoteByNode "p2p";
        };
        nextHopIdentities = builtins.length (builtins.attrNames remoteGroups);
        materializedRouteRows =
          builtins.foldl'
            (acc: row: acc + builtins.length (row.routes4 or [ ]) + builtins.length (row.routes6 or [ ]))
            0
            routeRows;
        nodes = builtins.length nodeNames;
      };
    in
    trace.emit "routing:internal:site-plan:nodes=${toString diagnostics.nodes}:planner=${diagnostics.planner}:tenantAtoms=${toString diagnostics.routeAtoms.tenant}:overlayAtoms=${toString diagnostics.routeAtoms.overlay}:p2pAtoms=${toString diagnostics.routeAtoms.p2p}" {
      inherit byNode diagnostics;
    };
}
