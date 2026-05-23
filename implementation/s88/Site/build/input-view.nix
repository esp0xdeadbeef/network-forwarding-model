{
  lib,
  utils,
  trace,
  transitMod,
  inputRoleMod,
}:
{
  enterprise,
  siteId,
  site,
}:

let
  topologyNodes =
    if
      site ? topology
      && builtins.isAttrs site.topology
      && site.topology ? nodes
      && builtins.isAttrs site.topology.nodes
    then
      site.topology.nodes
    else
      { };

  siteNodes = if site ? nodes && builtins.isAttrs site.nodes then site.nodes else { };
  siteUnits = if site ? units && builtins.isAttrs site.units then site.units else { };

  forwardingSemanticsNodes =
    if
      site ? forwardingSemantics
      && builtins.isAttrs site.forwardingSemantics
      && site.forwardingSemantics ? nodes
      && builtins.isAttrs site.forwardingSemantics.nodes
    then
      site.forwardingSemantics.nodes
    else
      { };

  nodesBase = forwardingSemanticsNodes // topologyNodes // siteNodes // siteUnits;
  roleFromInputExplicit = inputRoleMod.roleFromSite site;

  rawOrdering = utils.requireAttr "sites.${enterprise}.${siteId}.transit.ordering" (
    site.transit.ordering or null
  );

  rawOrderingPairs = trace.emit "site:${enterprise}.${siteId}:normalize-ordering" (
    (transitMod.normalizeInputOrdering {
      siteName = "${enterprise}.${siteId}";
      ordering = rawOrdering;
    }).pairs
  );

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

  overlayAttachmentItems =
    let
      attachments = site.overlayAttachments or { };
    in
    if builtins.isAttrs attachments then builtins.attrValues attachments else [ ];

  attachmentsForNode =
    nodeName:
    (nodesBase.${nodeName}.attachments or [ ])
    ++ lib.filter (att: toString (att.unit or "") == nodeName) (site.attachments or [ ]);

  nodeHasTenant =
    nodeName: tenantName:
    lib.any (
      attachment:
      (attachment.kind or null) == "tenant" && toString (attachment.name or "") == toString tenantName
    ) (attachmentsForNode nodeName);

  isOverlayUnderlayPair =
    pair:
    let
      a = toString (builtins.elemAt pair 0);
      b = toString (builtins.elemAt pair 1);
      roleA = roleFromInputExplicit a;
      roleB = roleFromInputExplicit b;
      core =
        if roleA == "core" && roleB == "access" then
          a
        else if roleB == "core" && roleA == "access" then
          b
        else
          null;
      access =
        if roleA == "access" && roleB == "core" then
          a
        else if roleB == "access" && roleA == "core" then
          b
        else
          null;
    in
    core != null
    && access != null
    && (
      lib.any (
        overlay:
        (overlay.terminateOn or null) == core
        && (overlay.underlayAccess.kind or null) == "tenant"
        && nodeHasTenant access (overlay.underlayAccess.name or "")
      ) overlayItems
      || lib.any (
        attachment:
        builtins.elem core (map toString (attachment.terminatesOn or [ ]))
        && builtins.elem access (map toString (attachment.accessNodes or [ ]))
      ) overlayAttachmentItems
    );

  canonicalOrderingPairs = lib.filter (pair: !(isOverlayUnderlayPair pair)) rawOrderingPairs;
in
{
  inherit
    topologyNodes
    siteNodes
    siteUnits
    forwardingSemanticsNodes
    nodesBase
    roleFromInputExplicit
    rawOrderingPairs
    canonicalOrderingPairs
    ;
}
