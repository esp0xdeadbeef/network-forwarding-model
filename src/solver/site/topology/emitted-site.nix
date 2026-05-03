{ lib }:

let
  common = import ./common.nix { inherit lib; };
  transit = import ./transit.nix { inherit lib; };
  roleStages = import ../../../../lib/fabric/transit-role-stages.nix { };
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

      finalPolicyNodeName =
        if normalizedRouteSite ? policyNodeName && normalizedRouteSite.policyNodeName != null then
          normalizedRouteSite.policyNodeName
        else if policyNodeName != null then
          policyNodeName
        else
          common.firstNodeNameByRole (normalizedRouteSite.nodes or { }) "policy";

      finalCoreNodeNames =
        if normalizedRouteSite ? coreNodeNames && normalizedRouteSite.coreNodeNames != [ ] then
          normalizedRouteSite.coreNodeNames
        else
          coreNodeNames;

      emittedUpstreamSelectorNodeName =
        let
          nodes = normalizedRouteSite.nodes or { };

          candidate =
            if
              normalizedRouteSite ? upstreamSelectorNodeName && normalizedRouteSite.upstreamSelectorNodeName != null
            then
              normalizedRouteSite.upstreamSelectorNodeName
            else if upstreamSelectorNodeName != null then
              upstreamSelectorNodeName
            else
              common.firstNodeNameByRole nodes "upstream-selector";
        in
        if
          candidate != null
          && nodes ? "${candidate}"
          && (nodes.${candidate}.role or null) == "upstream-selector"
        then
          candidate
        else
          null;

      validateUpstreamSelectorNodeName =
        if emittedUpstreamSelectorNodeName == null then
          true
        else if
          (normalizedRouteSite.nodes or { } ? "${emittedUpstreamSelectorNodeName}")
          && ((normalizedRouteSite.nodes.${emittedUpstreamSelectorNodeName}.role or null) == "upstream-selector")
        then
          true
        else
          throw ''
            network-forwarding-model: invalid emitted upstreamSelectorNodeName

            site: ${enterprise}.${siteId}
            candidate: ${toString emittedUpstreamSelectorNodeName}
            nodes: ${builtins.toJSON (builtins.attrNames (normalizedRouteSite.nodes or { }))}
          '';

      realizedTransitAdjacencies = transit.transitAdjacenciesFromLinks (normalizedRouteSite.links or { });

      transitAdjacencyOrderKey =
        adj:
        let
          members = adj.members or [ ];
          memberA = toString (builtins.elemAt members 0);
          memberB = toString (builtins.elemAt members 1);
          memberARank = roleStages.transitRankOrFallback 9 (rolesResult.roleFromInput memberA);
          memberBRank = roleStages.transitRankOrFallback 9 (rolesResult.roleFromInput memberB);
          oriented =
            if memberARank < memberBRank then
              {
                src = memberA;
                dst = memberB;
                rank = memberARank;
              }
            else
              {
                src = memberB;
                dst = memberA;
                rank = memberBRank;
              };
        in
        "${toString oriented.rank}|${oriented.src}|${oriented.dst}|${toString (adj.name or "")}";

      transitOrdering =
        let
          p2pAdjacencies = lib.filter (adj: (adj.kind or null) == "p2p") realizedTransitAdjacencies;
          orderedIds = map (adj: toString adj.id) (
            lib.sort (a: b: (transitAdjacencyOrderKey a) < (transitAdjacencyOrderKey b)) p2pAdjacencies
          );

          expectedIds = lib.sort (a: b: a < b) (map (adj: toString adj.id) realizedTransitAdjacencies);
          actualIds = lib.sort (a: b: a < b) orderedIds;

          uniqueOrdering =
            if (builtins.length orderedIds) == (builtins.length (lib.unique orderedIds)) then
              true
            else
              throw ''
                network-forwarding-model: transit.ordering contains duplicate link identities

                site: ${enterprise}.${siteId}
                ordering: ${builtins.toJSON orderedIds}
              '';

          completeOrdering =
            if actualIds == expectedIds then
              true
            else
              throw ''
                network-forwarding-model: transit.ordering is incomplete or inconsistent with realized topology

                site: ${enterprise}.${siteId}
                expected: ${builtins.toJSON expectedIds}
                actual: ${builtins.toJSON actualIds}
              '';
        in
        builtins.seq uniqueOrdering (builtins.seq completeOrdering orderedIds);

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

      emittedUplinkCoreNames =
        let
          routedNames =
            if normalizedRouteSite ? uplinkCoreNames && builtins.isList normalizedRouteSite.uplinkCoreNames then
              normalizedRouteSite.uplinkCoreNames
            else
              [ ];

          wanNames =
            if wanResult ? declaredUplinkCores && builtins.isList wanResult.declaredUplinkCores then
              wanResult.declaredUplinkCores
            else if wanResult ? uplinkCores && builtins.isList wanResult.uplinkCores then
              wanResult.uplinkCores
            else
              [ ];

          egressNames =
            if normalizedRouteSite ? egressIntent && builtins.isAttrs normalizedRouteSite.egressIntent then
              normalizedRouteSite.egressIntent.uplinkCoreNodeNames or [ ]
            else
              [ ];
        in
        lib.sort (a: b: a < b) (
          lib.unique (
            if wanNames != [ ] then
              wanNames
            else if routedNames != [ ] then
              routedNames
            else
              egressNames
          )
        );

      emittedUplinkNames =
        let
          routedNames =
            if normalizedRouteSite ? uplinkNames && builtins.isList normalizedRouteSite.uplinkNames then
              normalizedRouteSite.uplinkNames
            else
              [ ];

          wanNames =
            if wanResult ? declaredUplinkNames && builtins.isList wanResult.declaredUplinkNames then
              wanResult.declaredUplinkNames
            else if wanResult ? uplinkNames && builtins.isList wanResult.uplinkNames then
              wanResult.uplinkNames
            else
              [ ];

          egressNames =
            if normalizedRouteSite ? egressIntent && builtins.isAttrs normalizedRouteSite.egressIntent then
              normalizedRouteSite.egressIntent.externalDomains or [ ]
            else
              [ ];
        in
        lib.sort (a: b: a < b) (
          lib.unique (
            if routedNames != [ ] then
              routedNames
            else if wanNames != [ ] then
              wanNames
            else
              egressNames
          )
        );
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
