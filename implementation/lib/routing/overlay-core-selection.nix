{ lib, self ? { outPath = ./.; }, ... }:

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

  attachmentTargets =
    attachment:
    let
      targets = attachment.terminatesOn or attachment.terminateOn or attachment.targets or [ ];
    in
    if builtins.isList targets then map toString targets else [ (toString targets) ];

  overlayAttachmentItems =
    topo:
    let
      attachments = topo.overlayAttachments or { };
    in
    if builtins.isAttrs attachments then builtins.attrValues attachments else [ ];

  overlayTerminatingCores =
    topo:
    lib.unique (
      (lib.concatMap overlayTargets (overlayItems topo))
      ++ (lib.concatMap attachmentTargets (overlayAttachmentItems topo))
    );
in
{
  inherit overlayTerminatingCores;

  underlayAccessNodesForCore =
    topo: coreName:
    let
      attachments = overlayAttachmentItems topo;
      matchingAttachments = lib.filter
        (
          attachment: builtins.elem (toString coreName) (attachmentTargets attachment)
        )
        attachments;
    in
    lib.unique (
      lib.concatMap
        (attachment: map toString (attachment.accessNodes or [ ]))
        matchingAttachments
    );

  nonOverlayUplinkCores =
    topo: uplinkCores:
    let
      overlayCores = overlayTerminatingCores topo;
      nonOverlayCores = lib.filter (coreName: !(builtins.elem coreName overlayCores)) uplinkCores;
    in
    if nonOverlayCores == [ ] then uplinkCores else nonOverlayCores;
}
