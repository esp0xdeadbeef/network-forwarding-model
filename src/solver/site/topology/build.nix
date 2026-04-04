{ lib }:

let
  p2pAlloc = import ../../../../lib/p2p/alloc.nix { inherit lib; };
  topoResolve = import ../../../../lib/topology-resolve.nix { inherit lib; };
  addr = import ../../../../lib/model/addressing.nix { inherit lib; };

  common = import ./common.nix { inherit lib; };
  domains = import ./domains.nix { inherit lib; };
  tenants = import ./tenants.nix { inherit lib; };
  overlays = import ./overlays.nix { inherit lib; };
  pools = import ./pools.nix { inherit lib; };
  transit = import ./transit.nix { inherit lib; };

in
{
  build =
    {
      lib,
      site,
      siteId,
      enterprise,
      ordering,
      p2pPool,
      rolesResult,
      wanResult,
      enforcementResult,
      sites ? { },
    }:
    let
      siteName = toString (site.siteName or "${enterprise}.${siteId}");
      localPool = site.addressPools.local or null;

      siteDomains = domains.materializeSiteDomains site;

      overlayReachability = overlays.overlayReachabilityForSite {
        inherit enterprise;
        site = site // {
          domains = siteDomains;
        };
        allSites = sites;
      };

      siteForTopology = site // {
        domains = siteDomains;
      };

      orderingUnits = lib.unique (
        lib.concatMap (
          p: if builtins.isList p && builtins.length p == 2 then map toString p else [ ]
        ) ordering
      );

      topologyNodeNames =
        if
          site ? topology
          && builtins.isAttrs site.topology
          && site.topology ? nodes
          && builtins.isAttrs site.topology.nodes
        then
          builtins.attrNames site.topology.nodes
        else
          [ ];

      unitNames = lib.sort (a: b: a < b) (
        lib.unique (
          (if site ? units && builtins.isAttrs site.units then builtins.attrNames site.units else [ ])
          ++ (if site ? nodes && builtins.isAttrs site.nodes then builtins.attrNames site.nodes else [ ])
          ++ topologyNodeNames
          ++ orderingUnits
          ++ (rolesResult.traversal.chain or [ ])
          ++ builtins.attrNames (rolesResult.traversal.inferred or { })
        )
      );

      p2pPairs = lib.filter (p: builtins.isList p && builtins.length p == 2) ordering;
      loopbackHostBase = 0;

      explicitLoopbackByUnit = builtins.listToAttrs (
        map (unitName: {
          name = unitName;
          value = pools.explicitLoopbackFromSite site unitName;
        }) unitNames
      );

      nodes = lib.listToAttrs (
        lib.imap0 (idx: u: {
          name = toString u;
          value =
            let
              unitName = toString u;
              base = common.nodeFromSite site unitName;
              attachedNetworks = tenants.tenantNetworksForUnit siteForTopology unitName;
              explicitLoopback = explicitLoopbackByUnit.${unitName} or null;

              alloc4 =
                if localPool != null && (localPool.ipv4 or null) != null then
                  addr.hostCidr (loopbackHostBase + idx) "${common.stripMask localPool.ipv4}/32"
                else
                  null;

              alloc6 =
                if localPool != null && (localPool.ipv6 or null) != null then
                  addr.hostCidr (loopbackHostBase + idx) "${common.stripMask localPool.ipv6}/128"
                else
                  null;

              loopback =
                let
                  final4 =
                    if explicitLoopback != null && (explicitLoopback.ipv4 or null) != null then
                      explicitLoopback.ipv4
                    else
                      alloc4;

                  final6 =
                    if explicitLoopback != null && (explicitLoopback.ipv6 or null) != null then
                      explicitLoopback.ipv6
                    else
                      alloc6;
                in
                if final4 == null && final6 == null then
                  null
                else
                  {
                    ipv4 = final4;
                    ipv6 = final6;
                  };
            in
            base
            // {
              role = rolesResult.roleFromInput unitName;
              containers = base.containers or [ "default" ];
            }
            // lib.optionalAttrs (attachedNetworks != { }) {
              networks = attachedNetworks;
            }
            // lib.optionalAttrs (loopback != null) {
              inherit loopback;
            };
        }) unitNames
      );

      explicitLoopbackEntries = pools.explicitLoopbackEntriesFromUnits site unitNames;
      userPrefixes =
        (pools.userPrefixEntriesFromNodes nodes) ++ (tenants.tenantPrefixEntriesFromDomains siteDomains);

      _validateP2pPool4 = pools.validatePool {
        label = "sites.${enterprise}.${siteId}.addressPools.p2p.ipv4";
        family = 4;
        cidrStr = p2pPool.ipv4 or null;
        requiredHosts = 2 * (builtins.length p2pPairs);
        required = true;
      };

      _validateP2pPool6 = pools.validatePool {
        label = "sites.${enterprise}.${siteId}.addressPools.p2p.ipv6";
        family = 6;
        cidrStr = p2pPool.ipv6 or null;
        requiredHosts = if (p2pPool.ipv6 or null) == null then 0 else 2 * (builtins.length p2pPairs);
        required = false;
      };

      _validateLocalPool4 = pools.validatePool {
        label = "sites.${enterprise}.${siteId}.addressPools.local.ipv4";
        family = 4;
        cidrStr = if localPool == null then null else localPool.ipv4 or null;
        requiredHosts =
          if localPool == null || (localPool.ipv4 or null) == null then 0 else builtins.length unitNames;
        required = true;
      };

      _validateLocalPool6 = pools.validatePool {
        label = "sites.${enterprise}.${siteId}.addressPools.local.ipv6";
        family = 6;
        cidrStr = if localPool == null then null else localPool.ipv6 or null;
        requiredHosts =
          if localPool == null || (localPool.ipv6 or null) == null then 0 else builtins.length unitNames;
        required = false;
      };

      _disjointPools4 = pools.assertNoOverlap {
        leftLabel = "sites.${enterprise}.${siteId}.addressPools.p2p.ipv4";
        leftCidr = p2pPool.ipv4 or null;
        rightLabel = "sites.${enterprise}.${siteId}.addressPools.local.ipv4";
        rightCidr = if localPool == null then null else localPool.ipv4 or null;
      };

      _disjointPools6 = pools.assertNoOverlap {
        leftLabel = "sites.${enterprise}.${siteId}.addressPools.p2p.ipv6";
        leftCidr = p2pPool.ipv6 or null;
        rightLabel = "sites.${enterprise}.${siteId}.addressPools.local.ipv6";
        rightCidr = if localPool == null then null else localPool.ipv6 or null;
      };

      _poolsVsUserPrefixes = lib.forEach userPrefixes (
        entry:
        builtins.seq
          (pools.assertNoOverlap {
            leftLabel = "sites.${enterprise}.${siteId}.addressPools.p2p";
            leftCidr = if entry.family == 4 then p2pPool.ipv4 or null else p2pPool.ipv6 or null;
            rightLabel = entry.label;
            rightCidr = entry.cidr;
          })
          (
            pools.assertNoOverlap {
              leftLabel = "sites.${enterprise}.${siteId}.addressPools.local";
              leftCidr =
                if localPool == null then
                  null
                else if entry.family == 4 then
                  localPool.ipv4 or null
                else
                  localPool.ipv6 or null;
              rightLabel = entry.label;
              rightCidr = entry.cidr;
            }
          )
      );

      _explicitLoopbacksInLocalPool = lib.forEach explicitLoopbackEntries (
        entry:
        pools.assertHostInPool {
          poolLabel = "sites.${enterprise}.${siteId}.addressPools.local";
          poolCidr =
            if localPool == null then
              null
            else if entry.family == 4 then
              localPool.ipv4 or null
            else
              localPool.ipv6 or null;
          entryLabel = entry.label;
          family = entry.family;
          addr0 = entry.addr;
        }
      );

      p2pLinks = builtins.seq _validateP2pPool4 (
        builtins.seq _validateP2pPool6 (
          builtins.seq _validateLocalPool4 (
            builtins.seq _validateLocalPool6 (
              builtins.seq _disjointPools4 (
                builtins.seq _disjointPools6 (
                  builtins.deepSeq _poolsVsUserPrefixes (
                    builtins.deepSeq _explicitLoopbacksInLocalPool (
                      p2pAlloc.alloc {
                        site = {
                          siteName = siteName;
                          p2p-pool = p2pPool;
                          links = p2pPairs;
                          inherit nodes;
                          domains = siteDomains;
                        };
                      }
                    )
                  )
                )
              )
            )
          )
        )
      );

      coreNodeNames = lib.sort (a: b: a < b) (
        map toString (lib.filter (u: rolesResult.roleFromInput u == "core") unitNames)
      );

      policyNodeName = if rolesResult.policyUnit == null then null else toString rolesResult.policyUnit;

      upstreamSelectorNodeName =
        let
          selectorNames = lib.sort (a: b: a < b) (
            map toString (lib.filter (u: rolesResult.roleFromInput u == "upstream-selector") unitNames)
          );
        in
        if selectorNames == [ ] then null else builtins.head selectorNames;

      routed0 = topoResolve (
        siteForTopology
        // enforcementResult
        // {
          inherit
            siteName
            enterprise
            siteId
            coreNodeNames
            policyNodeName
            upstreamSelectorNodeName
            overlayReachability
            ;
          uplinkCoreNames = wanResult.uplinkCores or [ ];
          uplinkNames = wanResult.uplinkNames or [ ];
          p2p-pool = p2pPool;
          inherit nodes;
          links = p2pLinks // (wanResult.wanLinks or { }) // (site.links or { });
        }
      );

      routed1 = routed0 // {
        nodes = lib.mapAttrs (
          _: node:
          node
          // {
            interfaces = lib.mapAttrs (_: common.normalizeRoutes) (node.interfaces or { });
          }
        ) (routed0.nodes or { });
      };

      finalPolicyNodeName =
        if routed1 ? policyNodeName && routed1.policyNodeName != null then
          routed1.policyNodeName
        else if policyNodeName != null then
          policyNodeName
        else
          common.firstNodeNameByRole (routed1.nodes or { }) "policy";

      finalCoreNodeNames =
        if routed1 ? coreNodeNames && routed1.coreNodeNames != [ ] then
          routed1.coreNodeNames
        else
          coreNodeNames;

      emittedUpstreamSelectorNodeName =
        let
          nodes1 = routed1.nodes or { };

          candidate =
            if routed1 ? upstreamSelectorNodeName && routed1.upstreamSelectorNodeName != null then
              routed1.upstreamSelectorNodeName
            else if upstreamSelectorNodeName != null then
              upstreamSelectorNodeName
            else
              common.firstNodeNameByRole nodes1 "upstream-selector";
        in
        if
          candidate != null
          && nodes1 ? "${candidate}"
          && (nodes1.${candidate}.role or null) == "upstream-selector"
        then
          candidate
        else
          null;

      _assertUpstreamSelectorNodeName =
        if emittedUpstreamSelectorNodeName == null then
          true
        else if
          (routed1.nodes or { } ? "${emittedUpstreamSelectorNodeName}")
          && ((routed1.nodes.${emittedUpstreamSelectorNodeName}.role or null) == "upstream-selector")
        then
          true
        else
          throw ''
            network-forwarding-model: invalid emitted upstreamSelectorNodeName

            site: ${enterprise}.${siteId}
            candidate: ${toString emittedUpstreamSelectorNodeName}
            nodes: ${builtins.toJSON (builtins.attrNames (routed1.nodes or { }))}
          '';

      realizedTransitAdjacencies = transit.transitAdjacenciesFromLinks (routed1.links or { });

      transitOrdering =
        let
          ids = map (pair: transit.transitLinkIdForPair (routed1.links or { }) pair) p2pPairs;

          expected = lib.sort (a: b: a < b) (map (adj: toString adj.id) realizedTransitAdjacencies);

          actual = lib.sort (a: b: a < b) ids;

          _unique =
            if (builtins.length ids) == (builtins.length (lib.unique ids)) then
              true
            else
              throw ''
                network-forwarding-model: transit.ordering contains duplicate link identities

                site: ${enterprise}.${siteId}
                ordering: ${builtins.toJSON ids}
              '';

          _complete =
            if actual == expected then
              true
            else
              throw ''
                network-forwarding-model: transit.ordering is incomplete or inconsistent with realized topology

                site: ${enterprise}.${siteId}
                expected: ${builtins.toJSON expected}
                actual: ${builtins.toJSON actual}
              '';
        in
        builtins.seq _unique (builtins.seq _complete ids);

      finalUplinkCoreNames = routed1.uplinkCoreNames or (wanResult.uplinkCores or [ ]);

      sortedStrings = xs: lib.sort (a: b: a < b) (lib.unique (map toString xs));

      wanInterfaceNamesForNode =
        nodeName:
        let
          ifaces = (routed1.nodes.${nodeName}.interfaces or { });
        in
        lib.sort (a: b: a < b) (
          lib.filter (ifName: (ifaces.${ifName}.kind or null) == "wan") (builtins.attrNames ifaces)
        );

      uplinkNamesForNode =
        nodeName:
        let
          ifaces = (routed1.nodes.${nodeName}.interfaces or { });
        in
        sortedStrings (
          map (
            ifName:
            let
              iface = ifaces.${ifName};
            in
            toString (iface.uplink or iface.upstream or ifName)
          ) (wanInterfaceNamesForNode nodeName)
        );

      forwardingMarkerForNode =
        nodeName:
        rolesResult.forwardingMarkers.${nodeName} or {
          role = routed1.nodes.${nodeName}.role or null;
          functions = [ ];
          traversal = {
            participates = false;
            chainIndex = null;
            entry = false;
            terminal = false;
            incoming = [ ];
            outgoing = [ ];
          };
          responsibilities = {
            accessTermination = false;
            policyEnforcement = false;
            transitForwarding = false;
          };
          authority = {
            attachedPrefixRouting = false;
            transitRouting = false;
            upstreamSelection = false;
          };
        };

      egressMarkersForNode =
        nodeName:
        let
          wanInterfaces = wanInterfaceNamesForNode nodeName;
          uplinkNames = uplinkNamesForNode nodeName;
          authority = (lib.elem nodeName finalUplinkCoreNames) || wanInterfaces != [ ];
          upstreamSelection =
            emittedUpstreamSelectorNodeName != null && nodeName == emittedUpstreamSelectorNodeName;
        in
        {
          authority = authority;
          upstreamSelection = upstreamSelection;
          exitEligible = authority;
          wanInterfaces = wanInterfaces;
          uplinkNames = uplinkNames;
          candidateExitNodes = if upstreamSelection then finalUplinkCoreNames else [ ];
        };

      existingTopology =
        if routed1 ? topology && builtins.isAttrs routed1.topology then routed1.topology else { };

      existingTransit =
        if routed1 ? transit && builtins.isAttrs routed1.transit then routed1.transit else { };

      routed =
        builtins.removeAttrs routed1 [
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
          siteName = routed1.siteName or siteName;
          coreNodeNames = finalCoreNodeNames;
          policyNodeName = finalPolicyNodeName;
          upstreamSelectorNodeName = builtins.seq _assertUpstreamSelectorNodeName emittedUpstreamSelectorNodeName;
          uplinkCoreNames = finalUplinkCoreNames;
          uplinkNames = routed1.uplinkNames or (wanResult.uplinkNames or [ ]);
          nodes = lib.mapAttrs (
            nodeName: node:
            node
            // {
              forwarding = forwardingMarkerForNode nodeName;
              egress = egressMarkersForNode nodeName;
            }
          ) (routed1.nodes or { });
          topology = (builtins.removeAttrs existingTopology [ "nodes" ]) // {
            links = existingTopology.links or [ ];
          };
          transit = existingTransit // {
            ordering = transitOrdering;
            adjacencies = realizedTransitAdjacencies;
          };
        };
    in
    routed;
}
