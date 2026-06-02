{ lib }:

let
  groupValues = keyFn: xs: builtins.groupBy keyFn xs;

in
{
  build =
    { includeOverlay
    , includeP2p
    , includeTenant
    , nodeNames
    , nodes
    , remotePrefixFacts
    ,
    }:
    let
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
          policyScoped = overlayName != null && builtins.hasAttr overlayName remotePrefixFacts.overlayPolicyAllowedNodes;
          attachmentScoped = overlayName != null && builtins.hasAttr overlayName remotePrefixFacts.overlayAllowedNodes;
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
          if entry.kind == "tenant" || entry.kind == "runtime-routed-prefix" then
            tenantReachableFromNode nodeName entry
            && !((entry.kind or null) == "runtime-routed-prefix" && nodeRole == "access")
          else if entry.kind == "overlay" then
            overlayAllowedOnNode nodeName entry
          else
            true
        );

      normalizeTenantEntry =
        entry:
        ({
          family = entry.family;
          owner = entry.owner;
          kind = entry.kind or "tenant";
        }
        // lib.optionalAttrs (entry ? dst) { dst = entry.dst; }
        // lib.optionalAttrs (entry ? sourceFile) {
          sourceFile = entry.sourceFile;
          prefixName = entry.prefixName or null;
          delegatedPrefixLength = entry.delegatedPrefixLength or null;
          perTenantPrefixLength = entry.perTenantPrefixLength or null;
          slot = entry.slot or null;
        }
        // lib.optionalAttrs ((entry.prefixPostfix or null) != null) { prefixPostfix = entry.prefixPostfix; });

      entriesByKind =
        (if includeP2p then remotePrefixFacts.p2pEntries else [ ])
        ++ (if includeTenant then map normalizeTenantEntry (remotePrefixFacts.tenantOwnerEntries or [ ]) else [ ])
        ++ (if includeOverlay then remotePrefixFacts.overlayRouteEntries else [ ]);

      rowsForEntry =
        entry:
        let
          eligibleNodeNames = builtins.filter (nodeName: sourceEligibleForEntry nodeName entry) nodeNames;
          baseRows = map (nodeName: { inherit nodeName entry; }) eligibleNodeNames;
          serviceScopes =
            if (entry.kind or null) == "tenant" then
              remotePrefixFacts.serviceRouteScopesByOwner.${entry.owner} or [ ]
            else
              [ ];
          scopedRows = lib.concatMap
            (scope: map (nodeName: { inherit nodeName; entry = entry // { routeScope = scope; }; }) eligibleNodeNames)
            serviceScopes;
        in
        baseRows ++ scopedRows;

      sourceRows = lib.concatMap rowsForEntry entriesByKind;
      resolutionKey =
        row:
        let
          e = row.entry;
          routeScope = e.routeScope or { };
        in
        "${row.nodeName}|${toString (e.owner or "")}|${toString (e.kind or "")}|${toString (e.overlay or "")}|${toString (e.peerSite or "")}|${toString (routeScope.access or "")}|${toString (routeScope.uplink or "")}|${toString (routeScope.serviceName or "")}";
    in
    {
      inherit entriesByKind sourceRows;
      remoteGroups = groupValues resolutionKey sourceRows;
    };
}
