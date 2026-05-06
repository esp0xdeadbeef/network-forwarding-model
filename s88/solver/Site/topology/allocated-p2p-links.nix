{ lib }:

let
  p2pAlloc = import ../../../../lib/p2p/alloc.nix { inherit lib; };
  pools = import ./pools.nix { inherit lib; };
in
{
  allocate =
    {
      enterprise,
      siteId,
      siteName,
      localPool,
      p2pPool,
      p2pLinkSpecs,
      nodes,
      siteDomains,
      userPrefixes,
      explicitLoopbackEntries,
    }:
    let
      validateP2pIpv4Pool = pools.validatePool {
        label = "sites.${enterprise}.${siteId}.addressPools.p2p.ipv4";
        family = 4;
        cidrStr = p2pPool.ipv4 or null;
        requiredHosts = 2 * (builtins.length p2pLinkSpecs);
        required = true;
      };

      validateP2pIpv6Pool = pools.validatePool {
        label = "sites.${enterprise}.${siteId}.addressPools.p2p.ipv6";
        family = 6;
        cidrStr = p2pPool.ipv6 or null;
        requiredHosts = if (p2pPool.ipv6 or null) == null then 0 else 2 * (builtins.length p2pLinkSpecs);
        required = false;
      };

      validateLocalIpv4Pool = pools.validatePool {
        label = "sites.${enterprise}.${siteId}.addressPools.local.ipv4";
        family = 4;
        cidrStr = if localPool == null then null else localPool.ipv4 or null;
        requiredHosts =
          if localPool == null || (localPool.ipv4 or null) == null then 0 else builtins.length (builtins.attrNames nodes);
        required = true;
      };

      validateLocalIpv6Pool = pools.validatePool {
        label = "sites.${enterprise}.${siteId}.addressPools.local.ipv6";
        family = 6;
        cidrStr = if localPool == null then null else localPool.ipv6 or null;
        requiredHosts =
          if localPool == null || (localPool.ipv6 or null) == null then 0 else builtins.length (builtins.attrNames nodes);
        required = false;
      };

      disjointIpv4Pools = pools.assertNoOverlap {
        leftLabel = "sites.${enterprise}.${siteId}.addressPools.p2p.ipv4";
        leftCidr = p2pPool.ipv4 or null;
        rightLabel = "sites.${enterprise}.${siteId}.addressPools.local.ipv4";
        rightCidr = if localPool == null then null else localPool.ipv4 or null;
      };

      disjointIpv6Pools = pools.assertNoOverlap {
        leftLabel = "sites.${enterprise}.${siteId}.addressPools.p2p.ipv6";
        leftCidr = p2pPool.ipv6 or null;
        rightLabel = "sites.${enterprise}.${siteId}.addressPools.local.ipv6";
        rightCidr = if localPool == null then null else localPool.ipv6 or null;
      };

      poolsDoNotOverlapUserPrefixes = lib.forEach userPrefixes (
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

      explicitLoopbacksInLocalPool = lib.forEach explicitLoopbackEntries (
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
    in
    builtins.seq validateP2pIpv4Pool (
      builtins.seq validateP2pIpv6Pool (
        builtins.seq validateLocalIpv4Pool (
          builtins.seq validateLocalIpv6Pool (
            builtins.seq disjointIpv4Pools (
              builtins.seq disjointIpv6Pools (
                builtins.deepSeq poolsDoNotOverlapUserPrefixes (
                  builtins.deepSeq explicitLoopbacksInLocalPool (
                    p2pAlloc.alloc {
                      site = {
                        inherit siteName nodes;
                        p2p-pool = p2pPool;
                        links = p2pLinkSpecs;
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
}
