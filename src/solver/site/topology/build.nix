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
  semantics = import ./semantics.nix { inherit lib; };

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

      # ---- Lane derivation helpers ----

      firstUnitByRole =
        role:
        let
          names = lib.sort (a: b: a < b) unitNames;
          hits = lib.filter (n: rolesResult.roleFromInput (toString n) == role) names;
        in
        if hits == [ ] then null else toString (builtins.head hits);

      downstreamSelectorUnit = firstUnitByRole "downstream-selector";
      upstreamSelectorUnit = firstUnitByRole "upstream-selector";
      policyUnit = if rolesResult.policyUnit == null then null else toString rolesResult.policyUnit;
      accessUnitNames =
        let
          names = lib.sort (a: b: a < b) unitNames;
        in
        map toString (lib.filter (n: rolesResult.roleFromInput (toString n) == "access") names);

      # Map unit -> attached tenant names.
      tenantsByAccessUnit =
        let
          attachments = site.attachments or [ ];
          step =
            acc: a:
            if !(builtins.isAttrs a) then
              acc
            else
              let
                unit = toString (a.unit or "");
                kind = toString (a.kind or "");
                name = toString (a.name or "");
              in
              if unit == "" || kind != "tenant" || name == "" then
                acc
              else
                acc
                // {
                  "${unit}" = (acc.${unit} or [ ]) ++ [ name ];
                };
        in
        builtins.foldl' step { } attachments;

      relationToUplinkNames =
        rel:
        let
          to = rel.to or { };
          kind = to.kind or null;
          uplinks = to.uplinks or null;
          name = to.name or null;
        in
        if kind != "external" then
          [ ]
        else if builtins.isList uplinks then
          map toString uplinks
        else if name != null && toString name != "" then
          [ (toString name) ]
        else
          [ ];

      relationAppliesToAccessUnit =
        unit: rel:
        let
          from = rel.from or { };
          unitTenants = tenantsByAccessUnit.${unit} or [ ];
          kind = from.kind or null;
        in
        if kind == "tenant" then
          builtins.elem (toString (from.name or "")) unitTenants
        else if kind == "tenant-set" then
          let
            members = if builtins.isList (from.members or null) then map toString from.members else [ ];
          in
          lib.any (t: builtins.elem t members) unitTenants
        else
          false;

      # Per-access uplinks are a conservative superset: any "allow" relation to external uplinks.
      # Precise deny/priority semantics should stay in the upstream policy contract.
      allowedUplinksByAccessUnit =
        let
          relations = (site.communicationContract.allowedRelations or [ ]);
          hasAnyAllowRelation = lib.any (rel: (rel.action or null) == "allow") relations;

          # When the forwarding-model is used directly (without the compiler), sites may omit
          # explicit allow-relations. In that case, assume "no contract == no restriction" and
          # allow all uplinks that exist in the site definition.
          allUplinkNames =
            let
              cores = (site.upstreams.cores or { });
              coreNames = builtins.attrNames cores;
              names = lib.concatMap (
                coreName: map (u: toString (u.name or "")) (cores.${coreName} or [ ])
              ) coreNames;
            in
            lib.sort (a: b: a < b) (lib.unique (lib.filter (s: s != "") names));

          mkForUnit =
            unit:
            let
              uplinks =
                if !hasAnyAllowRelation then
                  allUplinkNames
                else
                  lib.concatMap (
                    rel:
                    if (rel.action or null) == "allow" && relationAppliesToAccessUnit unit rel then
                      relationToUplinkNames rel
                    else
                      [ ]
                  ) relations;
            in
            {
              name = unit;
              value = lib.sort (a: b: a < b) (lib.unique (lib.filter (s: s != "") (map toString uplinks)));
            };
        in
        builtins.listToAttrs (map mkForUnit accessUnitNames);

      baseP2pPairs = lib.filter (p: builtins.isList p && builtins.length p == 2) topologyPairs;

      isPair =
        a: b: pair:
        let
          x = toString (builtins.elemAt pair 0);
          y = toString (builtins.elemAt pair 1);
        in
        (x == a && y == b) || (x == b && y == a);

      p2pNameWithSuffix =
        a: b: suffix:
        let
          a0 = toString a;
          b0 = toString b;
          left = if a0 < b0 then a0 else b0;
          right = if a0 < b0 then b0 else a0;
        in
        "p2p-${left}-${right}--${toString suffix}";

      basePairsWithoutSelectorBuses =
        if policyUnit == null then
          baseP2pPairs
        else
          lib.filter (
            pair:
            let
              dropDsPolicy = downstreamSelectorUnit != null && isPair policyUnit downstreamSelectorUnit pair;
              dropPolicyUp = upstreamSelectorUnit != null && isPair policyUnit upstreamSelectorUnit pair;
            in
            !(dropDsPolicy || dropPolicyUp)
          ) baseP2pPairs;

      # Derived links:
      # - downstream-selector <-> policy: one lane per access unit (policy enforces per ingress lane)
      # - policy <-> upstream-selector: one lane per (access unit, allowed uplink)
      derivedLaneSpecs =
        if policyUnit == null then
          [ ]
        else
          (lib.concatMap (
            accessUnit:
            if downstreamSelectorUnit == null then
              [ ]
            else
              [
                {
                  a = policyUnit;
                  b = downstreamSelectorUnit;
                  lane = "access::${toString accessUnit}";
                  name = p2pNameWithSuffix policyUnit downstreamSelectorUnit "access-${toString accessUnit}";
                }
              ]
          ) accessUnitNames)
          ++ (lib.concatMap (
            accessUnit:
            let
              uplinks = allowedUplinksByAccessUnit.${toString accessUnit} or [ ];
            in
            if upstreamSelectorUnit == null then
              [ ]
            else
              map (uplinkName: {
                a = policyUnit;
                b = upstreamSelectorUnit;
                lane = "access::${toString accessUnit}::uplink::${toString uplinkName}";
                name =
                  p2pNameWithSuffix policyUnit upstreamSelectorUnit
                    "access-${toString accessUnit}--uplink-${toString uplinkName}";
              }) uplinks
          ) accessUnitNames);

      p2pLinkSpecs = (map (p: p) basePairsWithoutSelectorBuses) ++ derivedLaneSpecs;

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
        requiredHosts = 2 * (builtins.length p2pLinkSpecs);
        required = true;
      };

      _validateP2pPool6 = pools.validatePool {
        label = "sites.${enterprise}.${siteId}.addressPools.p2p.ipv6";
        family = 6;
        cidrStr = p2pPool.ipv6 or null;
        requiredHosts = if (p2pPool.ipv6 or null) == null then 0 else 2 * (builtins.length p2pLinkSpecs);
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
                          links = p2pLinkSpecs;
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
          stageRank =
            role:
            if role == "access" then
              0
            else if role == "downstream-selector" then
              1
            else if role == "policy" then
              2
            else if role == "upstream-selector" then
              3
            else if role == "core" then
              4
            else
              9;

          linkOrderKey =
            adj:
            let
              ms = adj.members or [ ];
              a = toString (builtins.elemAt ms 0);
              b = toString (builtins.elemAt ms 1);
              ra = rolesResult.roleFromInput a;
              rb = rolesResult.roleFromInput b;
              rka = stageRank ra;
              rkb = stageRank rb;
              oriented =
                if rka < rkb then
                  {
                    src = a;
                    dst = b;
                    rank = rka;
                  }
                else
                  {
                    src = b;
                    dst = a;
                    rank = rkb;
                  };
            in
            "${toString oriented.rank}|${oriented.src}|${oriented.dst}|${toString (adj.name or "")}";

          p2pAdj = lib.filter (a: (a.kind or null) == "p2p") realizedTransitAdjacencies;
          ids = map (adj: toString adj.id) (lib.sort (x: y: (linkOrderKey x) < (linkOrderKey y)) p2pAdj);

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

      existingTopology =
        if routed1 ? topology && builtins.isAttrs routed1.topology then routed1.topology else { };

      existingTransit =
        if routed1 ? transit && builtins.isAttrs routed1.transit then routed1.transit else { };

      emittedUplinkCoreNames =
        let
          routedNames =
            if routed1 ? uplinkCoreNames && builtins.isList routed1.uplinkCoreNames then
              routed1.uplinkCoreNames
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
            if routed1 ? egressIntent && builtins.isAttrs routed1.egressIntent then
              routed1.egressIntent.uplinkCoreNodeNames or [ ]
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

      emittedUplinkNames =
        let
          routedNames =
            if routed1 ? uplinkNames && builtins.isList routed1.uplinkNames then routed1.uplinkNames else [ ];

          wanNames =
            if wanResult ? declaredUplinkNames && builtins.isList wanResult.declaredUplinkNames then
              wanResult.declaredUplinkNames
            else if wanResult ? uplinkNames && builtins.isList wanResult.uplinkNames then
              wanResult.uplinkNames
            else
              [ ];

          egressNames =
            if routed1 ? egressIntent && builtins.isAttrs routed1.egressIntent then
              routed1.egressIntent.externalDomains or [ ]
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
            ordering = transitOrdering;
            adjacencies = realizedTransitAdjacencies;
          };
        };

      annotated = semantics.annotateSite {
        inherit rolesResult wanResult;
        site = routed;
      };
    in
    annotated;
}
