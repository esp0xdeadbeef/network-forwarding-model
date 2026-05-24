{ lib, ... }:

let
  tenantAttachments = node:
    lib.filter (tenant: tenant != null) (
      map
        (attachment:
          if (attachment.kind or null) == "tenant" then toString (attachment.name or null) else null)
        (node.attachments or [ ])
    );
in
{
  isHostLikeOverlayCore =
    { overlayNames
    , nodes
    ,
    }:
    nodeName:
    let
      node = nodes.${nodeName};
      uplinkNames = builtins.attrNames (node.uplinks or { });
    in
    tenantAttachments node != [ ]
    && uplinkNames != [ ]
    && builtins.all (uplinkName: builtins.elem uplinkName overlayNames) uplinkNames;
}
