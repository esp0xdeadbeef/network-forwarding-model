{
  lib,
  self ? {
    outPath = ./.;
  },
  ...
}:

let
  pathAvoidance = import ./graph/path-avoidance.nix { inherit lib; };
in
{
  # Selects the nearest reachable core/underlay access node that a non-core node
  # should send its generic default-reachability route toward. The path search
  # avoids overlay-terminating cores so overlay traffic is not reclassified as
  # underlay default.
  resolve =
    {
      topo,
      nodeName,
      routeGraph,
      nonOverlayTransitGraph ? null,
      routeFacts,
      overlayCoreSelection,
    }:
    let
      overlayTerminatingCores = overlayCoreSelection.overlayTerminatingCores topo;

      avoidsOverlayTransit =
        path:
        let
          len = builtins.length path;
          intermediate = if len <= 2 then [ ] else lib.sublist 1 (len - 2) path;
        in
        lib.all (node: !(builtins.elem node overlayTerminatingCores)) intermediate;

      shortestPathAvoiding =
        args:
        if nonOverlayTransitGraph == null then
          pathAvoidance.shortestPath routeGraph args
        else if args.src == args.dst then
          [ args.src ]
        else if builtins.elem args.src args.forbidden then
          null
        else
          nonOverlayTransitGraph.shortestPath {
            inherit (args) src dst;
          };

      nearestUplinkCore =
        let
          uplinks = routeFacts.uplinkCores or [ ];
          candidates = overlayCoreSelection.nonOverlayUplinkCores topo uplinks;
          reachable =
            lib.filter
              (
                candidate:
                candidate.path != null && builtins.length candidate.path >= 2 && avoidsOverlayTransit candidate.path
              )
              (
                map (target: {
                  inherit target;
                  path = shortestPathAvoiding {
                    src = nodeName;
                    dst = target;
                    forbidden = overlayTerminatingCores;
                  };
                }) candidates
              );
          sortedReachable = lib.sort (
            left: right:
            let
              leftLength = builtins.length left.path;
              rightLength = builtins.length right.path;
            in
            leftLength < rightLength || (leftLength == rightLength && left.target < right.target)
          ) reachable;
        in
        if uplinks == [ ] || lib.elem nodeName uplinks || sortedReachable == [ ] then
          null
        else
          (builtins.head sortedReachable).target;

      overlayUnderlayAccessNode =
        let
          accessNodes = overlayCoreSelection.underlayAccessNodesForCore topo nodeName;
          reachable = lib.filter (
            target:
            let
              path = routeGraph.shortestPath {
                src = nodeName;
                dst = target;
              };
            in
            path != null && builtins.length path >= 2
          ) accessNodes;
        in
        if reachable == [ ] then null else builtins.head (lib.sort (a: b: a < b) reachable);

      nearestDefaultTarget =
        if overlayUnderlayAccessNode != null then overlayUnderlayAccessNode else nearestUplinkCore;
    in
    {
      inherit
        nearestUplinkCore
        overlayUnderlayAccessNode
        nearestDefaultTarget
        shortestPathAvoiding
        ;
    };
}
