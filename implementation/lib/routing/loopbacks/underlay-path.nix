{
  lib,
  self ? {
    outPath = ./.;
  },
  ...
}:

let
  link = import (self.outPath + "/implementation/lib/topology/link-utils.nix") { inherit lib self; };
  overlayCoreSelection =
    import (self.outPath + "/implementation/lib/routing/overlay-core-selection.nix")
      {
        inherit lib self;
      };
  pathAvoidance = import (self.outPath + "/implementation/lib/routing/graph/path-avoidance.nix") {
    inherit lib;
  };
in
{
  selectedPath =
    {
      topo,
      routeGraph,
      src,
      dst,
      fallbackPath,
    }:
    let
      overlayTerminatingCores = overlayCoreSelection.overlayTerminatingCores topo;
      shortestPathAvoidingOverlayCores = pathAvoidance.shortestPath routeGraph;
      underlayAccessTargets =
        if dst == src then [ ] else overlayCoreSelection.underlayAccessNodesForCore topo dst;

      # The underlay path is authoritative only when the underlay access node
      # is a direct link neighbor of the overlay core. When the core is only
      # reachable through the fabric chain (no direct core<->access link), its
      # loopback must follow the normal fabric path; pointing the loopback at
      # a remote underlay access would install the route on the policy/
      # downstream lanes and shadow the core's own fabric link.
      directlyAttachedToCore =
        target:
        let
          links = topo.links or { };
          dstStr = toString dst;
          targetStr = toString target;
        in
        lib.any (
          linkName:
          let
            members = map toString (link.membersOf links.${linkName});
          in
          lib.elem dstStr members && lib.elem targetStr members
        ) (builtins.attrNames links);

      reachableUnderlayAccessTargets = lib.filter (
        target:
        directlyAttachedToCore target
        && (
          let
            accessPath = shortestPathAvoidingOverlayCores {
              inherit src;
              dst = target;
              forbidden = overlayTerminatingCores;
            };
          in
          accessPath != null && builtins.length accessPath >= 2
        )
      ) underlayAccessTargets;
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
