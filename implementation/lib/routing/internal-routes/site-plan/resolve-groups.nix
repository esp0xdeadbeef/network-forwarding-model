{ lib, self ? { outPath = ./.; }, ... }:

let
  helpers = import (self.outPath + "/implementation/lib/routing/static-helpers.nix") { inherit lib self; };
  link = import (self.outPath + "/implementation/lib/topology/link-utils.nix") { inherit lib self; };
  routeCandidates = import (self.outPath + "/implementation/lib/routing/internal-routes/route-candidates.nix");
  routeGroups = import (self.outPath + "/implementation/lib/routing/internal-routes/route-groups.nix") {
    inherit lib self;
  };

in
{
  build =
    { mkRoute4
    , mkRoute6
    , mode
    , realRouteGraph
    , remoteGroups
    , remotePrefixFacts
    , routeContext
    , routeFacts
    , routeGraph
    , topo
    ,
    }:
    let
      inherit (routeContext)
        loopbackOwnerNodeForDstWithFacts
        nextHopWithPreferredUplinks
        ;
      links = topo.links or { };
      groupValues = keyFn: xs: builtins.groupBy keyFn xs;

      resolveGroup =
        group:
        let
          nodeName = group.nodeName;
          dstEntry = builtins.head group.entries;
          routeScope = dstEntry.routeScope or null;
          primaryPath = routeGraph.shortestPath { src = nodeName; dst = dstEntry.owner; };
          firstHopHasRealLink =
            path:
            path != null
            && builtins.length path >= 2
            && routeGraph.linksBetween nodeName (builtins.elemAt path 1) != [ ];
          selectedRouteGraph = if firstHopHasRealLink primaryPath then routeGraph else realRouteGraph;
          path = selectedRouteGraph.shortestPath { src = nodeName; dst = dstEntry.owner; };
        in
        if path == null || builtins.length path < 2 then
          [ ]
        else
          let
            hop = builtins.elemAt path 1;
            uplinksForCore =
              coreName:
              lib.filter
                (uplinkName: builtins.elem coreName (routeFacts.uplinkCoreNamesByUplink.${uplinkName} or [ ]))
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
              inherit topo preferredUplinks preferredAccessNodes;
              from = nodeName;
              to = hop;
              routeGraph = selectedRouteGraph;
            };
            candidateLinks = routeCandidates {
              inherit link lib nodeName preferredUplinks preferredAccessNodes routeContext topo;
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
                    destinationOwner = dstEntry.owner or null;
                    hopNode = hop;
                  }
              )
              candidateLinks
          );

      resolveGroupRows =
        group:
        let
          resolvedHops = resolveGroup group;
        in
        lib.concatMap (resolvedHop: map (entry: entry // resolvedHop) group.entries) resolvedHops;

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
          routeScope = sample.routeScope or { };
          built = routeGroups.build {
            inherit mkRoute4 mkRoute6 mode topo;
            entries = rows;
            linkName = sample.linkName;
            via4 = sample.via4;
            via6 = sample.via6;
          };
        in
          {
            inherit (sample) nodeName;
            inherit (built) linkName routes4 routes6;
            equivalenceKey = {
              sourceNode = sample.nodeName;
              destinationOwner = sample.destinationOwner or null;
              routeKind = sample.kind;
              overlay = sample.overlay or null;
              uplink = routeScope.uplink or null;
              access = routeScope.access or null;
              serviceName = routeScope.serviceName or null;
              hopNode = sample.hopNode or null;
              linkName = sample.linkName;
              family = sample.family;
              via4 = sample.via4 or null;
              via6 = sample.via6 or null;
              routeIntentClass =
                if sample.kind == "runtime-routed-prefix" then
                  "runtime-routed-prefix-return"
                else if sample.kind == "routed-public-ipv4" then
                  "routed-public-ipv4-return"
                else if sample.kind == "overlay" then
                  "overlay-reachability"
                else
                  "internal-reachability";
              routeAtomIds = map (entry: (entry.routeAtom or { }).id or null) rows;
              aggregationClass = sample.aggregationClass or null;
              exceptionClass = sample.exceptionClass or null;
            };
            diagnostics = built.diagnostics;
          };
    in
    map (key: buildRouteRow nextHopGroups.${key}) (builtins.attrNames nextHopGroups);
}
