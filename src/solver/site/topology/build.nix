{ lib }:

let
  derive = import ../../../util/derive.nix { inherit lib; };

  p2pAlloc = import ../../../../lib/p2p/alloc.nix { inherit lib; };

  topoResolve = import ../../../../lib/topology-resolve.nix { inherit lib; };

  firstOrNull = xs: if xs == [ ] then null else builtins.elemAt xs 0;

  normalizeInterfaceRoutes =
    iface:
    let
      routes =
        if iface ? routes && builtins.isAttrs iface.routes then
          {
            ipv4 = iface.routes.ipv4 or [ ];
            ipv6 = iface.routes.ipv6 or [ ];
          }
        else
          {
            ipv4 = iface.routes4 or [ ];
            ipv6 = iface.routes6 or [ ];
          };
    in
    (builtins.removeAttrs iface [ "routes4" "routes6" ])
    // {
      routes = routes;
    };

  normalizeNode =
    node:
    let
      ifs = node.interfaces or { };
    in
    node // {
      interfaces = lib.mapAttrs (_: iface: normalizeInterfaceRoutes iface) ifs;
    };

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
        if rolesResult ? traversal && rolesResult.traversal ? chain then
          rolesResult.traversal.chain
        else
          [ ];

      inferredUnits =
        if rolesResult ? traversal && rolesResult.traversal ? inferred then
          builtins.attrNames rolesResult.traversal.inferred
        else
          [ ];

      unitsFromInput =
        if site ? units && builtins.isAttrs site.units then
          builtins.attrNames site.units
        else if site ? nodes && builtins.isAttrs site.nodes then
          builtins.attrNames site.nodes
        else
          [ ];

      unitNames =
        lib.unique (unitsFromInput ++ chainUnits ++ inferredUnits);

      mkUnitNode =
        u:
        let
          n = toString u;
          role = rolesResult.roleFromInput n;
          base =
            if site ? units && builtins.isAttrs site.units && site.units ? "${n}" then
              site.units.${n}
            else if site ? nodes && builtins.isAttrs site.nodes && site.nodes ? "${n}" then
              site.nodes.${n}
            else
              { };
        in
        base // {
          role = role;
          containers = base.containers or [ "default" ];
        };

      nodesUnits =
        lib.listToAttrs (map (n: { name = n; value = mkUnitNode n; }) unitNames);

      nodesMerged = nodesUnits;

      linkPairs =
        lib.filter
          (p: builtins.isList p && builtins.length p == 2)
          ordering;

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

      coreNodeNames =
        let
          cores = lib.filter (u: (rolesResult.roleFromInput u) == "core") unitNames;
        in
        lib.sort (a: b: a < b) (map toString cores);

      _haveCores =
        if coreNodeNames == [ ] then
          throw "network-solver: missing core unit for coreNodeNames"
        else
          true;

      policyNodeName =
        if rolesResult ? policyUnit && rolesResult.policyUnit != null then
          toString rolesResult.policyUnit
        else
          null;

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

          coreNodeNames = coreNodeNames;
          policyNodeName = policyNodeName;
          upstreamSelectorNodeName = upstreamSelectorNodeName;
          uplinkCoreNames = wanResult.uplinkCores or [ ];
          uplinkNames = wanResult.uplinkNames or [ ];

          p2p-pool = p2pPool;

          nodes = nodesMerged;
          links = linksMerged;
        };

      routed0 = topoResolve topoRaw;

      routed1 = routed0 // {
        nodes = lib.mapAttrs (_: node: normalizeNode node) (routed0.nodes or { });
      };

      routed =
        builtins.removeAttrs routed1 [
          "_enforcement"
          "_nat"
          "p2p-pool"
          "tenantV4Base"
          "ulaPrefix"
        ]
        // {
          siteName = routed1.siteName or siteName;
          enterprise = enterprise;
          siteId = siteId;
          coreNodeNames = routed1.coreNodeNames or coreNodeNames;
          policyNodeName = routed1.policyNodeName or policyNodeName;
          upstreamSelectorNodeName = routed1.upstreamSelectorNodeName or upstreamSelectorNodeName;
          uplinkCoreNames = routed1.uplinkCoreNames or (wanResult.uplinkCores or [ ]);
          uplinkNames = routed1.uplinkNames or (wanResult.uplinkNames or [ ]);
          nat = {
            mode = (routed1._nat.mode or "none");
            owner = routed1._nat.owner or null;
            ingress = routed1._nat.ingress or [ ];
          };
          policy = {
            owner = routed1._enforcement.owner or null;
            rules = routed1._enforcement.rules or [ ];
            validExternalRefs = routed1._enforcement.validExternalRefs or [ ];
          };
          aggregation = {
            mode = "none";
          };
        };

      query = import ../../../../lib/query/summary.nix { inherit lib routed; };

    in
    builtins.seq _haveCores (
      routed
      // {
        inherit query;
      }
    );
}
