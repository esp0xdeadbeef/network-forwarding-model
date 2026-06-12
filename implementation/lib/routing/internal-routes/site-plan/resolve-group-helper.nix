{ lib, helpers, defaultRoutePolicy, link, remotePrefixFacts, routeCandidates, routeGraph, realRouteGraph, routeFacts, routeContext, topo }:

let
  inherit (routeContext)
    loopbackOwnerNodeForDstWithFacts
    nextHopWithPreferredUplinks
    ;
  links = topo.links or { };
in
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
    tenantDefaultUplinks =
      if dstEntry.kind == "tenant" && (dstEntry.owner or null) != null then
        defaultRoutePolicy.anyTrafficDefaultUplinksForAccess topo dstEntry.owner
      else
        [ ];
    tenantNonOverlayDefaultUplinks =
      lib.filter
        (uplinkName: builtins.elem uplinkName (routeFacts.nonOverlayUplinkNames or [ ]))
        tenantDefaultUplinks;
    tenantPreferredDefaultUplinks =
      if tenantNonOverlayDefaultUplinks != [ ] then
        tenantNonOverlayDefaultUplinks
      else
        tenantDefaultUplinks;
    preferredUplinks =
      if routeScope != null && (routeScope.uplink or null) != null then
        [ routeScope.uplink ]
      else if dstEntry.kind == "overlay" && (dstEntry.overlay or null) != null then
        [ dstEntry.overlay ]
      else if dstEntry.kind == "p2p" && builtins.hasAttr (dstEntry.owner or "") (routeFacts.uplinkCoreSet or { }) then
        uplinksForCore dstEntry.owner
      else if tenantPreferredDefaultUplinks != [ ] then
        tenantPreferredDefaultUplinks
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
  )
