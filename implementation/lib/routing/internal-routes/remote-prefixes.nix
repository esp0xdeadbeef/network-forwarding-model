{ lib, self ? { outPath = ./.; }, ... }:

let
  helpers = import (self.outPath + "/implementation/lib/routing/static-helpers.nix") { inherit lib self; };
  link = import (self.outPath + "/implementation/lib/topology/link-utils.nix") { inherit lib self; };
  overlayScope = import ./overlay-scope.nix { inherit lib; };
  nodeFacts = import ./remote-prefixes/node-facts.nix { inherit lib; };
  laneMetadata = import (self.outPath + "/implementation/lib/routing/lane-metadata.nix") {
    inherit lib self;
  };
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
      overlayPolicyAllowedNodes = overlayScopeFacts.policyAllowedNodes;
      overlayAllowedNodes = overlayScopeFacts.attachmentAllowedNodes;

      addUnique = acc: name: value:
        acc // { "${name}" = lib.unique ((acc.${name} or [ ]) ++ [ value ]); };

      linkFacts =
        builtins.foldl'
          (
            acc: linkName:
              let
                linkObj = links.${linkName};
                uplinkName = laneUplinkName linkObj;
                accessNodeName = laneAccessNodeName linkObj;
                members = link.membersOf linkObj;
                accWithNodeUplinks =
                  if accessNodeName != null || uplinkName == null then
                    acc
                  else
                    builtins.foldl'
                      (
                        nodeAcc: member: nodeAcc // { uplinksByNode = addUnique nodeAcc.uplinksByNode member uplinkName; }
                      )
                      acc
                      members;
              in
              if accessNodeName == null || uplinkName == null then
                accWithNodeUplinks
              else
                accWithNodeUplinks // {
                  uplinksByAccess = addUnique accWithNodeUplinks.uplinksByAccess accessNodeName uplinkName;
                }
          )
          { uplinksByNode = { }; uplinksByAccess = { }; }
          linkNames;

      p2pByOwner = builtins.listToAttrs (
        map
          (owner: {
            name = owner;
            value =
              let
                prefixes = builtins.attrValues (helpers.prefixSetFromP2pIfaces nodes.${owner});
                concreteEntries = map
                  (
                    x:
                    x
                    // {
                      owner = owner;
                      kind = "p2p";
                    }
                  )
                  prefixes;
              in
              concreteEntries;
          })
          nodeNames
      );

      p2pEntries = lib.concatMap (owner: p2pByOwner.${owner} or [ ]) nodeNames;

      overlayRouteEntries = lib.concatMap
        (
          overlay:
          let
            owners = overlay.terminateOn or [ ];
            v4s = map (r: { family = 4; dst = r.dst or null; }) (overlay.routes4 or [ ]);
            v6s = map (r: { family = 6; dst = r.dst or null; }) (overlay.routes6 or [ ]);
            prefixes = lib.filter (e: e.dst != null) (v4s ++ v6s);
          in
          lib.concatMap
            (
              owner:
              map
                (
                  e:
                  e
                  // {
                    owner = owner;
                    kind = "overlay";
                    overlay = overlay.overlay or null;
                    peerSite = overlay.peerSite or null;
                  }
                )
                prefixes
            )
            owners
        )
        (builtins.attrValues (topo.overlayReachability or { }));

      ownConnectedPrefixSetByNode = builtins.listToAttrs (
        map
          (nodeName: {
            name = nodeName;
            value = helpers.ownConnectedPrefixes nodes.${nodeName};
          })
          nodeNames
      );

      remoteByNode =
        nodeFacts.build {
          inherit
            linkFacts
            nodeNames
            nodes
            overlayAllowedNodes
            overlayPolicyAllowedNodes
            overlayRouteEntries
            p2pEntries
            tenantOwnerEntries
            ;
        };
    in
    {
      inherit
        nodeNames
        ownConnectedPrefixSetByNode
        p2pByOwner
        p2pEntries
        overlayRouteEntries
        remoteByNode
        ;
      inherit tenantOwnerEntries;
      inherit overlayPolicyAllowedNodes;
      overlayEntries = builtins.attrValues (topo.overlayReachability or { });
      inherit overlayAllowedNodes;
      inherit (linkFacts) uplinksByNode uplinksByAccess;
    };

  byKindForNodeWithFacts =
    facts: _: nodeName:
      facts.remoteByNode.${nodeName} or {
        tenant = [ ];
        overlay = [ ];
        p2p = [ ];
      };
}
