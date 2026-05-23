{ lib }:

{
  site,
  firstEndpoint,
  secondEndpoint,
}:

let
  overlayItems =
    let
      overlays = ((site.transport or { }).overlays or [ ]);
    in
    if builtins.isList overlays then
      lib.filter (ov: ov != null && builtins.isAttrs ov) overlays
    else if builtins.isAttrs overlays then
      lib.mapAttrsToList (name: ov: ov // { inherit name; }) overlays
    else
      [ ];

  attachmentsForNode =
    nodeName:
    (site.topology.nodes.${nodeName}.attachments or [ ])
    ++ lib.filter (att: toString (att.unit or "") == nodeName) (site.attachments or [ ]);

  nodeHasUnderlayAccess =
    nodeName: selector:
    (selector.kind or null) == "tenant"
    && lib.any (
      att: (att.kind or null) == "tenant" && toString (att.name or "") == toString selector.name
    ) (attachmentsForNode nodeName);

  overlayAttachments = site.overlayAttachments or { };

  allowedByCompilerAttachment = lib.any (
    overlayName:
    let
      attachment = overlayAttachments.${overlayName};
      accessNodes = map toString (attachment.accessNodes or [ ]);
      coreNodes = map toString (attachment.terminatesOn or [ ]);
    in
    lib.elem firstEndpoint accessNodes && lib.elem secondEndpoint coreNodes
    || lib.elem secondEndpoint accessNodes && lib.elem firstEndpoint coreNodes
  ) (builtins.attrNames overlayAttachments);

  allowedByIntentOverlay = lib.any (
    overlay:
    let
      terminateOn = toString (overlay.terminateOn or "");
      underlayAccess = overlay.underlayAccess or null;
    in
    underlayAccess != null
    && (
      (firstEndpoint == terminateOn && nodeHasUnderlayAccess secondEndpoint underlayAccess)
      || (secondEndpoint == terminateOn && nodeHasUnderlayAccess firstEndpoint underlayAccess)
    )
  ) overlayItems;
in
allowedByCompilerAttachment || allowedByIntentOverlay
