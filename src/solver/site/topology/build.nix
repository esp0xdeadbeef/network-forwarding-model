{ lib }:

let
  topoResolve = import ../../../../lib/topology-resolve.nix { inherit lib; };
  addr = import ../../../../lib/model/addressing.nix { inherit lib; };

  common = import ./common.nix { inherit lib; };
  domains = import ./domains.nix { inherit lib; };
  tenants = import ./tenants.nix { inherit lib; };
  overlays = import ./overlays.nix { inherit lib; };
  pools = import ./pools.nix { inherit lib; };
  semantics = import ./semantics.nix { inherit lib; };
  laneLinks = import ./lane-links.nix { inherit lib; };
  allocatedP2pLinks = import ./allocated-p2p-links.nix { inherit lib; };
  emittedSite = import ./emitted-site.nix { inherit lib; };

in
{
  build =
    {
      lib,
      site,
      siteId,
      enterprise,
      ordering,
      linkPairs ? null,
      p2pPool,
      rolesResult,
      wanResult,
      enforcementResult,
      sites ? { },
    }:
    let
      siteName = toString (site.siteName or "${enterprise}.${siteId}");
      localPool = site.addressPools.local or null;
      topologyPairs = if linkPairs == null then ordering else linkPairs;

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
        ) topologyPairs
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

      forwardingSemanticsNodeNames =
        if
          site ? forwardingSemantics
          && builtins.isAttrs site.forwardingSemantics
          && site.forwardingSemantics ? nodes
          && builtins.isAttrs site.forwardingSemantics.nodes
        then
          builtins.attrNames site.forwardingSemantics.nodes
        else
          [ ];

      unitNames = lib.sort (a: b: a < b) (
        lib.unique (
          (if site ? units && builtins.isAttrs site.units then builtins.attrNames site.units else [ ])
          ++ (if site ? nodes && builtins.isAttrs site.nodes then builtins.attrNames site.nodes else [ ])
          ++ topologyNodeNames
          ++ forwardingSemanticsNodeNames
          ++ orderingUnits
          ++ (rolesResult.traversal.chain or [ ])
          ++ builtins.attrNames (rolesResult.traversal.inferred or { })
        )
      );

      laneLinkResult = laneLinks.derive {
        inherit
          rolesResult
          site
          topologyPairs
          unitNames
          wanResult
          ;
      };

      p2pLinkSpecs = laneLinkResult.p2pLinkSpecs;
      annotateMergedLinkLane = laneLinkResult.annotateMergedLinkLane;

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

      p2pLinks = allocatedP2pLinks.allocate {
        inherit
          enterprise
          explicitLoopbackEntries
          localPool
          nodes
          p2pLinkSpecs
          p2pPool
          siteDomains
          siteId
          siteName
          userPrefixes
          ;
      };

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

      resolvedSite = topoResolve (
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
          links = builtins.mapAttrs annotateMergedLinkLane (
            p2pLinks // (wanResult.wanLinks or { }) // (site.links or { })
          );
        }
      );

      routed = emittedSite.materialize {
        inherit
          coreNodeNames
          enterprise
          overlayReachability
          policyNodeName
          rolesResult
          siteId
          siteName
          topologyPairs
          upstreamSelectorNodeName
          wanResult
          ;
        routedSite = resolvedSite;
      };

      annotated = semantics.annotateSite {
        inherit rolesResult wanResult;
        site = routed;
      };
    in
    annotated;
}
