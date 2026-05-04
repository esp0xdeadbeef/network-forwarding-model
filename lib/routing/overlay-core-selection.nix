{ lib }:

let
  overlayItems =
    topo:
    let
      overlays = (topo.transport or { }).overlays or [ ];
    in
    if builtins.isList overlays then overlays else builtins.attrValues overlays;

  overlayTargets =
    overlay:
    let
      targets = overlay.terminateOn or overlay.targets or [ ];
    in
    if builtins.isList targets then map toString targets else [ (toString targets) ];

  overlayTerminatingCores =
    topo: lib.unique (lib.concatMap overlayTargets (overlayItems topo));
in
{
  nonOverlayUplinkCores =
    topo: uplinkCores:
    let
      overlayCores = overlayTerminatingCores topo;
      nonOverlayCores = lib.filter (coreName: !(builtins.elem coreName overlayCores)) uplinkCores;
    in
    if nonOverlayCores == [ ] then uplinkCores else nonOverlayCores;
}
