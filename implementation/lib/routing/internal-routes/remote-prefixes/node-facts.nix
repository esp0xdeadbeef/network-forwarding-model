{ lib, ... }:

{
  build =
    {
      linkFacts,
      nodeNames,
      nodes,
      overlayAllowedNodes,
      overlayPolicyAllowedNodes,
      overlayRouteEntries,
      p2pEntries,
      tenantOwnerEntries,
    }:
    let
      nodeRemote =
        nodeName:
        let
          node = nodes.${nodeName} or { };
          nodeRole = node.role or null;
          uplinksOnNode = linkFacts.uplinksByNode.${nodeName} or [ ];
          uplinksAllowedForAccess = accessNodeName: linkFacts.uplinksByAccess.${accessNodeName} or [ ];

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
            ) tenantOwnerEntries;

          overlayAllowedOnNode =
            entry:
            let
              overlayName = entry.overlay or null;
              policyScoped = overlayName != null && builtins.hasAttr overlayName overlayPolicyAllowedNodes;
              attachmentScoped = overlayName != null && builtins.hasAttr overlayName overlayAllowedNodes;
            in
            if policyScoped then
              builtins.elem nodeName overlayPolicyAllowedNodes.${overlayName}
            else if attachmentScoped then
              builtins.elem nodeName overlayAllowedNodes.${overlayName}
            else
              true;
        in
        {
          inherit tenant;
          overlay = lib.filter (entry: entry.owner != nodeName && overlayAllowedOnNode entry) overlayRouteEntries;
          p2p = lib.filter (entry: entry.owner != nodeName) p2pEntries;
        };
    in
    builtins.listToAttrs (
      map (nodeName: {
        name = nodeName;
        value = nodeRemote nodeName;
      }) nodeNames
    );
}
