{ lib, self ? { outPath = ./.; }, ... }:

let
  helpers = import (self.outPath + "/lib/routing/static-helpers.nix") { inherit lib self; };
  graph = import (self.outPath + "/lib/routing/graph.nix") { inherit lib self; };
  overlayScope = import ./overlay-scope.nix { inherit lib; };
  laneMetadata = import (self.outPath + "/implementation/lib/routing/lane-metadata.nix") {
    inherit lib self;
  };
  byNode = import ./remote-prefixes/by-node.nix { inherit lib; };
  inherit (laneMetadata)
    laneAccessNodeName
    laneUplinkName
    ;

in
rec {
  buildFacts =
    topo:
    let
      links = topo.links or { };
      nodes = topo.nodes or { };
      nodeNames = helpers.allNodeNames topo;
      linkNames = builtins.attrNames links;
      tenantOwnerEntries = builtins.attrValues (topo.tenantPrefixOwners or { });
      overlayScopeFacts = overlayScope.build topo tenantOwnerEntries;

      addUnique = acc: name: value:
        acc // { "${name}" = lib.unique ((acc.${name} or [ ]) ++ [ value ]); };

      linkFacts =
        builtins.foldl' (
          acc: linkName:
          let
            linkObj = links.${linkName};
            uplinkName = laneUplinkName linkObj;
            accessNodeName = laneAccessNodeName linkObj;
            members = graph.membersOf linkObj;
            accWithNodeUplinks =
              if accessNodeName != null || uplinkName == null then
                acc
              else
                builtins.foldl' (
                  nodeAcc: member: nodeAcc // { uplinksByNode = addUnique nodeAcc.uplinksByNode member uplinkName; }
                ) acc members;
          in
          if accessNodeName == null || uplinkName == null then
            accWithNodeUplinks
          else
            accWithNodeUplinks // {
              uplinksByAccess = addUnique accWithNodeUplinks.uplinksByAccess accessNodeName uplinkName;
            }
        ) { uplinksByNode = { }; uplinksByAccess = { }; } linkNames;

      p2pByOwner = builtins.listToAttrs (
        map
          (owner: {
            name = owner;
            value =
              let
                prefixes = builtins.attrValues (helpers.prefixSetFromP2pIfaces nodes.${owner});
                aggregateEntry =
                  family:
                  let
                    dst = helpers.buildP2pAggregate topo family;
                  in
                  if dst == null then
                    [ ]
                  else
                    [
                      {
                        inherit family dst owner;
                        kind = "p2p";
                      }
                    ];
                aggregateEntries = (aggregateEntry 4) ++ (aggregateEntry 6);
              in
              if aggregateEntries != [ ] then
                aggregateEntries
              else
                map (
                  x:
                  x
                  // {
                    owner = owner;
                    kind = "p2p";
                  }
                ) prefixes;
          })
          nodeNames
      );

      p2pEntries = lib.concatMap (owner: p2pByOwner.${owner} or [ ]) nodeNames;

      overlayRouteEntries = lib.concatMap (
        overlay:
        let
          owners = overlay.terminateOn or [ ];
          v4s = map (r: { family = 4; dst = r.dst or null; }) (overlay.routes4 or [ ]);
          v6s = map (r: { family = 6; dst = r.dst or null; }) (overlay.routes6 or [ ]);
          prefixes = lib.filter (e: e.dst != null) (v4s ++ v6s);
        in
        lib.concatMap (
          owner:
          map (
            e:
            e
            // {
              owner = owner;
              kind = "overlay";
              overlay = overlay.overlay or null;
              peerSite = overlay.peerSite or null;
            }
          ) prefixes
        ) owners
      ) (builtins.attrValues (topo.overlayReachability or { }));
    in
    {
      inherit nodeNames p2pByOwner p2pEntries overlayRouteEntries;
      inherit tenantOwnerEntries;
      overlayPolicyAllowedNodes = overlayScopeFacts.policyAllowedNodes;
      overlayEntries = builtins.attrValues (topo.overlayReachability or { });
      overlayAllowedNodes = overlayScopeFacts.attachmentAllowedNodes;
      inherit (linkFacts) uplinksByNode uplinksByAccess;
    };

  ofKindWithFacts =
    facts: topo: nodeName: kind:
    let
      nodes = topo.nodes or { };
      node = nodes.${nodeName} or { };
      nodeRole = node.role or null;

      tenantOwnerEntries = if kind == "tenant" then facts.tenantOwnerEntries else [ ];

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

      perTenantOwner =
        entry:
        if entry.owner == nodeName then
          [ ]
        else if !(tenantReachableFromNode entry) then
          [ ]
        else
          [
            {
              family = entry.family;
              dst = entry.dst;
              owner = entry.owner;
              kind = "tenant";
            }
          ];

      overlayAllowedOnNode =
        entry:
        let
          overlayName = entry.overlay or null;
          policyScoped =
            overlayName != null
            && builtins.hasAttr overlayName (facts.overlayPolicyAllowedNodes or { });
          attachmentScoped =
            overlayName != null
            && builtins.hasAttr overlayName (facts.overlayAllowedNodes or { });
        in
        if policyScoped then
          builtins.elem nodeName facts.overlayPolicyAllowedNodes.${overlayName}
        else if attachmentScoped then
          builtins.elem nodeName facts.overlayAllowedNodes.${overlayName}
        else
          true;

    in
    if kind == "tenant" then
      lib.concatMap perTenantOwner tenantOwnerEntries
    else if kind == "overlay" then
      lib.filter (entry: entry.owner != nodeName && overlayAllowedOnNode entry) (facts.overlayRouteEntries or [ ])
    else
      lib.filter (entry: entry.owner != nodeName) (facts.p2pEntries or [ ]);

  byKindForNodeWithFacts = byNode.byKind;

  ofKind = topo: nodeName: kind: ofKindWithFacts (buildFacts topo) topo nodeName kind;
}
