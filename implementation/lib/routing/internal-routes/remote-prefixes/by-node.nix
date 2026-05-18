{ lib, ... }:

{
  byKind =
    facts: topo: nodeName:
    let
      nodes = topo.nodes or { };
      node = nodes.${nodeName} or { };
      nodeRole = node.role or null;
      uplinksOnNode = facts.uplinksByNode.${nodeName} or [ ];
      uplinksAllowedForAccess = accessNodeName: facts.uplinksByAccess.${accessNodeName} or [ ];
      tenantReachableFromNode =
        entry:
        let
          allowedUplinks = uplinksAllowedForAccess entry.owner;
        in
        nodeRole != "core"
        || uplinksOnNode == [ ]
        || lib.any (uplinkName: builtins.elem uplinkName allowedUplinks) uplinksOnNode;
      tenant =
        lib.concatMap (
          entry:
          if entry.owner == nodeName || !(tenantReachableFromNode entry) then
            [ ]
          else
            [
              {
                family = entry.family;
                dst = entry.dst;
                owner = entry.owner;
                kind = "tenant";
              }
            ]
        ) (facts.tenantOwnerEntries or [ ]);
      overlayAllowedOnNode =
        entry:
        let
          overlayName = entry.overlay or null;
          policyScoped =
            overlayName != null && builtins.hasAttr overlayName (facts.overlayPolicyAllowedNodes or { });
          attachmentScoped =
            overlayName != null && builtins.hasAttr overlayName (facts.overlayAllowedNodes or { });
        in
        if policyScoped then
          builtins.elem nodeName facts.overlayPolicyAllowedNodes.${overlayName}
        else if attachmentScoped then
          builtins.elem nodeName facts.overlayAllowedNodes.${overlayName}
        else
          true;
    in
    {
      inherit tenant;
      overlay = lib.filter (entry: entry.owner != nodeName && overlayAllowedOnNode entry) (facts.overlayRouteEntries or [ ]);
      p2p = lib.filter (entry: entry.owner != nodeName) (facts.p2pEntries or [ ]);
    };
}
