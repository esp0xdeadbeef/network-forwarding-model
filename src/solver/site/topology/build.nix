{ lib }:

let
  derive = import ../../../util/derive.nix { inherit lib; };

  p2pAlloc = import ../../../../lib/p2p/alloc.nix { inherit lib; };

  topoResolve = import ../../../../lib/topology-resolve.nix { inherit lib; };

  firstOrNull = xs: if xs == [ ] then null else builtins.elemAt xs 0;

  requireStr =
    what: v:
    if v == null || !(builtins.isString v) || v == "" then
      throw "network-solver: missing required ${what}"
    else
      v;

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
    }:

    let
      siteName = toString (site.siteName or "${enterprise}.${siteId}");

      tenants = ((site.domains or { }).tenants or [ ]);

      t0 = firstOrNull tenants;

      tenantV4Base =
        if site ? tenantV4Base && builtins.isString site.tenantV4Base then
          site.tenantV4Base
        else if t0 != null && builtins.isAttrs t0 && t0 ? ipv4 then
          derive.tenantV4BaseFrom (toString t0.ipv4)
        else
          throw "network-solver: cannot derive tenantV4Base (missing site.tenantV4Base and domains.tenants[0].ipv4)";

      ulaPrefix =
        if site ? ulaPrefix && builtins.isString site.ulaPrefix then
          site.ulaPrefix
        else if t0 != null && builtins.isAttrs t0 && t0 ? ipv6 then
          derive.ulaPrefixFrom (toString t0.ipv6)
        else
          throw "network-solver: cannot derive ulaPrefix (missing site.ulaPrefix and domains.tenants[0].ipv6)";

      chainUnits =
        if rolesResult ? traversal && rolesResult.traversal ? chain
        then rolesResult.traversal.chain
        else [ ];

      inferredUnits =
        if rolesResult ? traversal && rolesResult.traversal ? inferred
        then builtins.attrNames rolesResult.traversal.inferred
        else [ ];

      unitsFromInput =
        if site ? units && builtins.isAttrs site.units then builtins.attrNames site.units
        else if site ? nodes && builtins.isAttrs site.nodes then builtins.attrNames site.nodes
        else [ ];

      unitNames =
        lib.unique (unitsFromInput ++ chainUnits ++ inferredUnits);

      mkUnitNode =
        u:
        let
          n = toString u;
          role = rolesResult.roleFromInput n;
          base =
            if site ? units && builtins.isAttrs site.units && site.units ? "${n}" then site.units.${n}
            else if site ? nodes && builtins.isAttrs site.nodes && site.nodes ? "${n}" then site.nodes.${n}
            else { };
        in
        base
        // {
          role = role;
          containers = base.containers or [ "default" ];
        };

      nodesUnits = lib.listToAttrs (map (n: { name = n; value = mkUnitNode n; }) unitNames);

      nodesMerged = nodesUnits // (wanResult.wanPeerNodes or { });

      linkPairs =
        map
          (e: [ (toString e.a) (toString e.b) ])
          (rolesResult.orderingEdges or [ ]);

      p2pSiteForAlloc =
        {
          p2p-pool = p2pPool;
          links = linkPairs;
          nodes = nodesMerged;
          domains = site.domains or { };
        };

      p2pLinks = p2pAlloc.alloc { site = p2pSiteForAlloc; };

      linksMerged =
        p2pLinks
        // (wanResult.wanLinks or { })
        // (site.links or { });

      coreNodeName =
        if wanResult ? coreUnit && wanResult.coreUnit != null then toString wanResult.coreUnit
        else
          let
            cores = lib.filter (u: (rolesResult.roleFromInput u) == "core") unitNames;
          in
          if cores == [ ] then throw "network-solver: missing core unit for coreNodeName"
          else builtins.elemAt (lib.sort (a: b: a < b) cores) 0;

      policyNodeName =
        if rolesResult ? policyUnit && rolesResult.policyUnit != null
        then toString rolesResult.policyUnit
        else null;

      upstreamSelectorNodeName =
        let
          ups = lib.filter (u: (rolesResult.roleFromInput u) == "upstream-selector") unitNames;
        in
        if ups == [ ] then null else builtins.elemAt (lib.sort (a: b: a < b) ups) 0;

      topoRaw =
        (if enforcementResult != null then enforcementResult else { })
        // {
          inherit siteName tenantV4Base ulaPrefix;
          enterprise = enterprise;
          siteId = siteId;

          coreNodeName = coreNodeName;
          policyNodeName = policyNodeName;
          upstreamSelectorNodeName = upstreamSelectorNodeName;

          p2p-pool = p2pPool;

          domains = site.domains or { };

          nodes = nodesMerged;
          links = linksMerged;

          compilerIR = site;
        };

      routed = topoResolve topoRaw;

      # IMPORTANT: keep output JSON-serializable (nix eval --json).
      # Queries are provided as a pure data summary (no lambdas).
      query = import ../../../../lib/query/summary.nix { inherit lib routed; };

    in
    routed
    // {
      inherit query;

      compilerIR = topoRaw.compilerIR;

      traversal =
        if rolesResult ? traversal then rolesResult.traversal else null;
    };
}
