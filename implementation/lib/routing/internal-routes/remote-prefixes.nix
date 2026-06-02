{ lib, self ? { outPath = ./.; }, ... }:

let
  helpers = import (self.outPath + "/implementation/lib/routing/static-helpers.nix") { inherit lib self; };
  overlayScope = import ./overlay-scope.nix { inherit lib; };
  nodeFacts = import ./remote-prefixes/node-facts.nix { inherit lib; };
  linkFactsBuilder = import ./remote-prefixes/link-facts.nix { inherit lib self; };
  routeEntriesBuilder = import ./remote-prefixes/route-entries.nix { inherit lib self; };
  serviceRouteScopes = import ./remote-prefixes/service-route-scopes.nix { inherit lib; };

in
rec {
  buildFacts =
    topo:
    let
      links = topo.links or { };
      nodes = topo.nodes or { };
      nodeNames = helpers.allNodeNames topo;
      tenantOwnerEntries = builtins.attrValues (topo.tenantPrefixOwners or { });
      overlayScopeFacts = overlayScope.build topo tenantOwnerEntries;
      overlayPolicyAllowedNodes = overlayScopeFacts.policyAllowedNodes;
      overlayAllowedNodes = overlayScopeFacts.attachmentAllowedNodes;

      linkFacts = linkFactsBuilder.build { inherit links; };
      routeEntries = routeEntriesBuilder.build {
        inherit
          helpers
          nodeNames
          nodes
          topo
          ;
      };
      serviceRouteScopesByOwner = serviceRouteScopes.build { inherit nodes topo; };

      remoteByNode =
        nodeFacts.build {
          inherit
            linkFacts
            nodeNames
            nodes
            overlayAllowedNodes
            overlayPolicyAllowedNodes
            tenantOwnerEntries
            ;
          inherit (routeEntries) overlayRouteEntries p2pEntries;
        };
    in
    {
      inherit
        nodeNames
        remoteByNode
        tenantOwnerEntries
        overlayPolicyAllowedNodes
        overlayAllowedNodes
        serviceRouteScopesByOwner
        ;
      inherit (linkFacts) uplinksByNode uplinksByAccess;
      inherit (routeEntries)
        ownConnectedPrefixSetByNode
        p2pByOwner
        p2pEntries
        overlayRouteEntries
        overlayEntries
        ;
    };

  byKindForNodeWithFacts =
    facts: _: nodeName:
      facts.remoteByNode.${nodeName} or {
        tenant = [ ];
        overlay = [ ];
        p2p = [ ];
      };
}
