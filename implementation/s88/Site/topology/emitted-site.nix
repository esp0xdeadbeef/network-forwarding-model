{ lib, self ? { outPath = ./.; }, ... }:

let
  common = import ./common.nix { inherit lib self; };
  transit = import ./transit.nix { inherit lib self; };
  roleNames = import (self.outPath + "/implementation/s88/Site/topology/emission/role-names.nix") {
    inherit lib self;
  };
  transitOrderingMod = import (self.outPath + "/implementation/s88/Site/topology/emission/transit-ordering.nix") {
    inherit lib self;
  };
  uplinkMetadata = import (self.outPath + "/implementation/s88/Site/topology/emission/uplink-metadata.nix") {
    inherit lib self;
  };
in
{
  materialize =
    {
      enterprise,
      siteId,
      siteName,
      topologyPairs,
      rolesResult,
      wanResult,
      policyNodeName,
      upstreamSelectorNodeName,
      coreNodeNames,
      overlayReachability,
      routedSite,
    }:
    let
      normalizedRouteSite = routedSite // {
        nodes = lib.mapAttrs (
          _: node:
          node
          // {
            interfaces = lib.mapAttrs (_: common.normalizeRoutes) (node.interfaces or { });
          }
        ) (routedSite.nodes or { });
      };

      finalPolicyNodeName = roleNames.finalPolicyNodeName { inherit normalizedRouteSite policyNodeName; };

      finalCoreNodeNames =
        if normalizedRouteSite ? coreNodeNames && normalizedRouteSite.coreNodeNames != [ ] then
          normalizedRouteSite.coreNodeNames
        else
          coreNodeNames;

      emittedUpstreamSelectorNodeName = roleNames.upstreamSelectorNodeName {
        inherit normalizedRouteSite upstreamSelectorNodeName;
      };

      validateUpstreamSelectorNodeName = roleNames.validateUpstreamSelector {
        inherit
          emittedUpstreamSelectorNodeName
          enterprise
          normalizedRouteSite
          siteId
          ;
      };

      realizedTransitAdjacencies = transit.transitAdjacenciesFromLinks (normalizedRouteSite.links or { });

      transitOrdering = transitOrderingMod.build {
        inherit enterprise siteId rolesResult realizedTransitAdjacencies;
      };

      existingTopology =
        if normalizedRouteSite ? topology && builtins.isAttrs normalizedRouteSite.topology then
          normalizedRouteSite.topology
        else
          { };

      existingTransit =
        if normalizedRouteSite ? transit && builtins.isAttrs normalizedRouteSite.transit then
          normalizedRouteSite.transit
        else
          { };

      emittedUplinkCoreNames = uplinkMetadata.coreNames { inherit normalizedRouteSite wanResult; };
      emittedUplinkNames = uplinkMetadata.uplinkNames { inherit normalizedRouteSite wanResult; };
    in
    builtins.removeAttrs normalizedRouteSite [
      "_enforcement"
      "_nat"
      "_loopbackResolution"
      "compilerIR"
      "p2p-pool"
      "pools"
      "tenantV4Base"
      "ulaPrefix"
      "routerLoopbacks"
      "transport"
    ]
    // {
      inherit enterprise siteId overlayReachability;
      siteName = normalizedRouteSite.siteName or siteName;
      coreNodeNames = finalCoreNodeNames;
      policyNodeName = finalPolicyNodeName;
      upstreamSelectorNodeName = builtins.seq validateUpstreamSelectorNodeName emittedUpstreamSelectorNodeName;
      uplinkCoreNames = emittedUplinkCoreNames;
      uplinkNames = emittedUplinkNames;
      topology =
        (builtins.removeAttrs existingTopology [
          "nodes"
          "links"
        ])
        // {
          links = topologyPairs;
        };
      transit = existingTransit // {
        dedicatedLanes = true;
        ordering = transitOrdering;
        adjacencies = realizedTransitAdjacencies;
      };
    };
}
