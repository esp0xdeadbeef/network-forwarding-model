{ lib, self ? { outPath = ./.; }, ... }:

let
  graph = import (self.outPath + "/lib/routing/graph.nix") { inherit lib self; };
  helpers = import (self.outPath + "/lib/routing/static-helpers.nix") { inherit lib self; };

in
{
  resolve =
    {
      topo,
      nodeName,
      dstEntry,
      routeContext,
      routeFacts ? routeContext.buildFacts topo,
      routeGraph ? graph.context (topo.links or { }),
    }:
    let
      inherit (routeContext) loopbackOwnerNodeForDstWithFacts nextHopWithPreferredUplinks;

      path = routeGraph.shortestPath {
        src = nodeName;
        dst = dstEntry.owner;
      };
    in
    if path == null || builtins.length path < 2 then
      null
    else
      let
        hop = builtins.elemAt path 1;
        preferredUplinks =
          if dstEntry.kind == "overlay" && (dstEntry.overlay or null) != null then
            [ dstEntry.overlay ]
          else if builtins.hasAttr (dstEntry.owner or "") (routeFacts.uplinkCoreSet or { }) then
            topo.uplinkNames or [ ]
          else
            [ ];
        preferredAccessNodes = lib.unique (
          lib.filter (x: x != null) [
            (dstEntry.owner or null)
            (loopbackOwnerNodeForDstWithFacts routeFacts dstEntry.family dstEntry.dst)
          ]
        );
        baseNh = nextHopWithPreferredUplinks {
          inherit topo;
          from = nodeName;
          to = hop;
          inherit routeGraph;
          inherit preferredUplinks preferredAccessNodes;
        };
        candidateLinks = import (self.outPath + "/implementation/lib/routing/internal-routes/route-candidates.nix") {
          inherit
            graph
            nodeName
            preferredUplinks
          routeContext
          topo
          ;
          inherit routeGraph;
          baseLinkName = baseNh.linkName;
          isOverlay = dstEntry.kind == "overlay";
          hopNode = hop;
        };
        nextHops = map (
          linkName:
          let
            linkObj = (topo.links or { }).${linkName};
            epTo = graph.getEp linkName linkObj hop;
          in
          {
            inherit linkName;
            via4 = if epTo ? addr4 && epTo.addr4 != null then helpers.stripMask epTo.addr4 else null;
            via6 = if epTo ? addr6 && epTo.addr6 != null then helpers.stripMask epTo.addr6 else null;
          }
        ) candidateLinks;
      in
      builtins.filter (entry: entry != null) (
        map (
          nh:
          if nh.linkName == null then
            null
          else if dstEntry.family == 4 && nh.via4 == null then
            null
          else if dstEntry.family == 6 && nh.via6 == null then
            null
          else
            dstEntry
            // {
              hopNode = hop;
              linkName = nh.linkName;
              via4 = nh.via4;
              via6 = nh.via6;
            }
        ) nextHops
      );
}
