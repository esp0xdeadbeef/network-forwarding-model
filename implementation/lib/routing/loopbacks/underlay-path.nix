{ lib, self ? { outPath = ./.; }, ... }:

let
  overlayCoreSelection = import (self.outPath + "/implementation/lib/routing/overlay-core-selection.nix") {
    inherit lib self;
  };
  pathAvoidance = import (self.outPath + "/implementation/lib/routing/graph/path-avoidance.nix") { inherit lib; };
in
{
  selectedPath =
    { topo
    , routeGraph
    , src
    , dst
    , fallbackPath
    ,
    }:
    let
      overlayTerminatingCores = overlayCoreSelection.overlayTerminatingCores topo;
      shortestPathAvoidingOverlayCores = pathAvoidance.shortestPath routeGraph;
      underlayAccessTargets =
        if dst == src then [ ] else overlayCoreSelection.underlayAccessNodesForCore topo dst;
      reachableUnderlayAccessTargets =
        lib.filter
          (
            target:
            let
              accessPath = shortestPathAvoidingOverlayCores {
                inherit src;
                dst = target;
                forbidden = overlayTerminatingCores;
              };
            in
            accessPath != null && builtins.length accessPath >= 2
          )
          underlayAccessTargets;
      selectedUnderlayAccess =
        if reachableUnderlayAccessTargets == [ ] then
          null
        else
          builtins.head (lib.sort (a: b: a < b) reachableUnderlayAccessTargets);
    in
    if selectedUnderlayAccess == null || selectedUnderlayAccess == src then
      fallbackPath
    else
      shortestPathAvoidingOverlayCores {
        inherit src;
        dst = selectedUnderlayAccess;
        forbidden = overlayTerminatingCores;
      };
}
