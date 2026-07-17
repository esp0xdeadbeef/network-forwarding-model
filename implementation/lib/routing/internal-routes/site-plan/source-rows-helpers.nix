{
  lib,
  mode,
  nodes,
  remotePrefixFacts,
}:

let
  str = value: if value == null then "" else toString value;

  aggregationClass =
    entry:
    if entry ? sourceFile then
      "runtime-source-file"
    else if
      mode == "none"
      || (entry.kind or null) == "p2p"
      || (entry.kind or null) == "overlay"
      || (entry.kind or null) == "routed-public-ipv4"
    then
      "exact-only"
    else
      "prefix-summary-eligible";

  exceptionClass =
    entry:
    if entry ? sourceFile then
      "runtime-source-file"
    else if (entry.kind or null) == "p2p" then
      "point-to-point-exact"
    else if (entry.overlay or null) != null then
      "overlay-scope-exact"
    else if (entry.uplink or null) != null then
      "selected-uplink-exact"
    else
      "none";

  routeAtomId =
    entry:
    builtins.concatStringsSep "|" [
      (str (entry.family or null))
      (str (entry.owner or null))
      (str (entry.kind or null))
      (str (entry.dst or null))
      (str (entry.sourceFile or null))
      (str (entry.tenant or entry.netName or null))
      (str (entry.prefixName or null))
      (str (entry.delegatedPrefixLength or null))
      (str (entry.perTenantPrefixLength or null))
      (str (entry.slot or null))
      (str (entry.prefixPostfix or null))
      (str (entry.overlay or null))
      (str (entry.uplink or null))
      (str (entry.peerSite or null))
    ];

  enrichEntry =
    entry:
    let
      atom = {
        id = routeAtomId entry;
        family = entry.family or null;
        destination = entry.dst or null;
        sourceFile = entry.sourceFile or null;
        tenant = entry.tenant or entry.netName or null;
        prefixName = entry.prefixName or null;
        delegatedPrefixLength = entry.delegatedPrefixLength or null;
        perTenantPrefixLength = entry.perTenantPrefixLength or null;
        slot = entry.slot or null;
        prefixPostfix = entry.prefixPostfix or null;
        owner = entry.owner or null;
        kind = entry.kind or null;
        overlay = entry.overlay or null;
        uplink = entry.uplink or null;
        peerSite = entry.peerSite or null;
        aggregationClass = aggregationClass entry;
        exceptionClass = exceptionClass entry;
      };
    in
    entry
    // {
      routeAtom = atom;
      aggregationClass = atom.aggregationClass;
      exceptionClass = atom.exceptionClass;
    };

  tenantReachableFromNode =
    nodeName: entry:
    let
      node = nodes.${nodeName} or { };
      nodeRole = node.role or null;
      uplinksOnNode = remotePrefixFacts.uplinksByNode.${nodeName} or [ ];
      allowedUplinks = remotePrefixFacts.uplinksByAccess.${entry.owner} or [ ];
    in
    nodeRole != "core"
    || uplinksOnNode == [ ]
    || builtins.any (uplinkName: builtins.elem uplinkName allowedUplinks) uplinksOnNode;

  overlayAllowedOnNode =
    nodeName: entry:
    let
      node = nodes.${nodeName} or { };
      nodeRole = node.role or null;
      uplinksOnNode = remotePrefixFacts.uplinksByNode.${nodeName} or [ ];
      overlayName = entry.overlay or null;
      policyScoped =
        overlayName != null && builtins.hasAttr overlayName remotePrefixFacts.overlayPolicyAllowedNodes;
      attachmentScoped =
        overlayName != null && builtins.hasAttr overlayName remotePrefixFacts.overlayAllowedNodes;
      isNonOverlayUplinkCore =
        nodeRole == "core"
        && overlayName != null
        && builtins.any (uplinkName: uplinkName != overlayName) uplinksOnNode;
    in
    if isNonOverlayUplinkCore then
      true
    else if policyScoped then
      builtins.elem nodeName remotePrefixFacts.overlayPolicyAllowedNodes.${overlayName}
    else if attachmentScoped then
      builtins.elem nodeName remotePrefixFacts.overlayAllowedNodes.${overlayName}
    else
      true;

  sourceEligibleForEntry =
    nodeName: entry:
    let
      node = nodes.${nodeName} or { };
      nodeRole = node.role or null;
      ownSet = remotePrefixFacts.ownConnectedPrefixSetByNode.${nodeName} or { };
      ownsDst = if entry ? dst then ownSet ? "${toString entry.family}|${entry.dst}" else false;
    in
    entry.owner != nodeName
    && !ownsDst
    && (
      if
        entry.kind == "tenant"
        || entry.kind == "runtime-routed-prefix"
        || entry.kind == "routed-public-ipv4"
      then
        tenantReachableFromNode nodeName entry
        && !((entry.kind or null) == "runtime-routed-prefix" && nodeRole == "access")
      else if entry.kind == "overlay" then
        overlayAllowedOnNode nodeName entry
      else
        true
    );

  normalizeTenantEntry =
    entry:
    (
      {
        family = entry.family;
        owner = entry.owner;
        kind = entry.kind or "tenant";
      }
      // lib.optionalAttrs (entry ? dst) { dst = entry.dst; }
      // lib.optionalAttrs ((entry.authorityClass or null) != null) {
        authorityClass = entry.authorityClass;
      }
      // lib.optionalAttrs ((entry.source or null) != null) { source = entry.source; }
      // lib.optionalAttrs (entry ? sourceFile) {
        sourceFile = entry.sourceFile;
        tenant = entry.tenant or entry.netName or null;
        prefixName = entry.prefixName or null;
        delegatedPrefixLength = entry.delegatedPrefixLength or null;
        perTenantPrefixLength = entry.perTenantPrefixLength or null;
        slot = entry.slot or null;
      }
      // lib.optionalAttrs ((entry.prefixPostfix or null) != null) {
        prefixPostfix = entry.prefixPostfix;
      }
    );

in
{
  inherit
    aggregationClass
    enrichEntry
    exceptionClass
    normalizeTenantEntry
    overlayAllowedOnNode
    routeAtomId
    sourceEligibleForEntry
    str
    tenantReachableFromNode
    ;
}
