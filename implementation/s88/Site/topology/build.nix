{ lib, self ? { outPath = ./.; }, ... }:

let
  topoResolve = import (self.outPath + "/lib/topology-resolve.nix") { inherit lib self; };

  domains = import ./domains.nix { inherit lib self; };
  tenants = import ./tenants.nix { inherit lib self; };
  overlays = import ./overlays.nix { inherit lib self; };
  pools = import ./pools.nix { inherit lib self; };
  topologyNodes = import ./nodes.nix { inherit lib self; };
  unitNamesMod = import ./unit-names.nix { inherit lib self; };
  semantics = import ./semantics.nix { inherit lib self; };
  laneLinks = import ./lane-links.nix { inherit lib self; };
  allocatedP2pLinks = import ./allocated-p2p-links.nix { inherit lib self; };
  emittedSite = import ./emitted-site.nix { inherit lib self; };

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

      unitNames = unitNamesMod.collect { inherit site topologyPairs rolesResult; };

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

      nodes = topologyNodes.build { inherit site siteForTopology unitNames localPool rolesResult; };

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
