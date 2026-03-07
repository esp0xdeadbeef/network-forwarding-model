{ lib }:

let
  requireAttr =
    path: v: if v == null then throw "network-solver: missing required attribute: ${path}" else v;

  safeHead =
    what: xs:
    if builtins.isList xs && xs != [ ] then
      builtins.head xs
    else
      throw "network-solver: expected at least one ${what}";

  split = sep: s: lib.splitString sep (toString s);

  isAttachmentLeaf =
    x:
    builtins.isAttrs x
    && (
      x ? kind
      || x ? segment
      || x ? tenant
      || x ? tenantName
      || x ? subject
      || x ? ingressSubject
      || x ? from
      || x ? to
    );

  flattenAttachmentSource =
    ownerHint: x:
    if builtins.isList x then
      lib.concatMap (flattenAttachmentSource ownerHint) x
    else if isAttachmentLeaf x then
      [ (x // lib.optionalAttrs (ownerHint != null && !(x ? unit) && !(x ? node)) { unit = ownerHint; }) ]
    else if builtins.isAttrs x then
      lib.concatMap (k: flattenAttachmentSource (toString k) x.${k}) (builtins.attrNames x)
    else
      [ ];

  attachmentsOf =
    site:
    let
      raw = if site ? attachments then site.attachments else site.attachment or [ ];
    in
    flattenAttachmentSource null raw;

  unitRefOfAttachment =
    a:
    if !builtins.isAttrs a then
      null
    else if a ? unit && a.unit != null then
      toString a.unit
    else if a ? node && a.node != null then
      toString a.node
    else if a ? target && builtins.isAttrs a.target && (a.target.unit or null) != null then
      toString a.target.unit
    else if a ? target && builtins.isAttrs a.target && (a.target.node or null) != null then
      toString a.target.node
    else if a ? to && builtins.isAttrs a.to && (a.to.unit or null) != null then
      toString a.to.unit
    else if a ? to && builtins.isAttrs a.to && (a.to.node or null) != null then
      toString a.to.node
    else
      null;
in
{
  inherit
    requireAttr
    safeHead
    split
    isAttachmentLeaf
    flattenAttachmentSource
    attachmentsOf
    unitRefOfAttachment
    ;
}
