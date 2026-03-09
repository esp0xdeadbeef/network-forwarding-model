{ lib }:

let
  derive = import ../../../util/derive.nix { inherit lib; };
  p2pAlloc = import ../../../../lib/p2p/alloc.nix { inherit lib; };
  topoResolve = import ../../../../lib/topology-resolve.nix { inherit lib; };
  utils = import ../../../util { inherit lib; };

  firstOrNull = xs: if xs == [ ] then null else builtins.head xs;

  normalizeRoutes =
    iface:
    (builtins.removeAttrs iface [
      "routes4"
      "routes6"
    ])
    // {
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
    };

  nodeFromSite =
    site: n:
    if site ? units && builtins.isAttrs site.units && site.units ? "${n}" then
      site.units.${n}
    else if site ? nodes && builtins.isAttrs site.nodes && site.nodes ? "${n}" then
      site.nodes.${n}
    else
      { };

  tenantCatalog =
    site:
    let
      tenants = (site.domains or { }).tenants or [ ];
    in
    builtins.listToAttrs (
      map (t: {
        name = toString t.name;
        value = {
          kind = t.kind or "tenant";
          name = toString t.name;
          ipv4 = t.ipv4 or null;
          ipv6 = t.ipv6 or null;
        };
      }) (lib.filter (t: builtins.isAttrs t && (t.name or null) != null) tenants)
    );

  tenantNameFromSegments =
    segments:
    let
      parts = lib.concatMap (
        seg:
        let
          s = toString seg;
          p = lib.splitString ":" s;
        in
        if builtins.length p == 2 then
          [
            {
              ns = builtins.elemAt p 0;
              name = builtins.elemAt p 1;
            }
          ]
        else
          [ ]
      ) segments;

      hits = lib.filter (x: (x.ns == "tenants" || x.ns == "tenant") && x.name != "") parts;
    in
    if hits == [ ] then null else (builtins.head hits).name;

  parseTenantNameFromAttachment =
    a:
    let
      kind = toString (a.kind or "");
      directName =
        if a ? tenant && a.tenant != null then
          toString a.tenant
        else if a ? tenantName && a.tenantName != null then
          toString a.tenantName
        else if a ? name && a.name != null && kind == "tenant" then
          toString a.name
        else if
          a ? subject
          && builtins.isAttrs a.subject
          && (a.subject.kind or null) == "tenant"
          && (a.subject.name or null) != null
        then
          toString a.subject.name
        else if
          a ? ingressSubject
          && builtins.isAttrs a.ingressSubject
          && (a.ingressSubject.kind or null) == "tenant"
          && (a.ingressSubject.name or null) != null
        then
          toString a.ingressSubject.name
        else if
          a ? from
          && builtins.isAttrs a.from
          && (a.from.kind or null) == "tenant"
          && (a.from.name or null) != null
        then
          toString a.from.name
        else if
          a ? to && builtins.isAttrs a.to && (a.to.kind or null) == "tenant" && (a.to.name or null) != null
        then
          toString a.to.name
        else
          null;

      segmentDerived = tenantNameFromSegments (
        lib.filter (s: s != null && s != "") [
          (a.segment or null)
          (a.path or null)
          (a.ref or null)
        ]
      );
    in
    if directName != null && directName != "" then directName else segmentDerived;

  inferTenantNamesFromUnitName =
    site: unitName:
    let
      catalog = tenantCatalog site;
      tenantNames = lib.sort (a: b: a < b) (builtins.attrNames catalog);

      lowerUnit = lib.toLower (toString unitName);

      matches = lib.filter (
        tenantName:
        let
          t = lib.toLower (toString tenantName);
        in
        lib.hasSuffix "-${t}" lowerUnit
        || lib.hasSuffix "_${t}" lowerUnit
        || lib.hasSuffix ":${t}" lowerUnit
        || lowerUnit == t
      ) tenantNames;
    in
    matches;

  attachedTenantNamesForUnit =
    site: unitName:
    let
      explicit = lib.unique (
        lib.filter (x: x != null && x != "") (
          map (
            a:
            let
              owner = utils.unitRefOfAttachment a;
            in
            if builtins.isAttrs a && owner == unitName then parseTenantNameFromAttachment a else null
          ) (utils.attachmentsOf site)
        )
      );

      inferred = inferTenantNamesFromUnitName site unitName;
    in
    if explicit != [ ] then explicit else inferred;

  tenantNetworksForUnit =
    site: unitName:
    let
      catalog = tenantCatalog site;
      names = attachedTenantNamesForUnit site unitName;
    in
    builtins.listToAttrs (
      map (name: {
        name = toString name;
        value = catalog.${name};
      }) (lib.filter (name: catalog ? "${name}") names)
    );

  policyIntentFromSite =
    site:
    let
      communicationContract =
        if
          site ? provenance
          && builtins.isAttrs site.provenance
          && site.provenance ? communicationContract
          && builtins.isAttrs site.provenance.communicationContract
        then
          site.provenance.communicationContract
        else if
          site ? provenance
          && builtins.isAttrs site.provenance
          && site.provenance ? originalInputs
          && builtins.isAttrs site.provenance.originalInputs
          && site.provenance.originalInputs ? communicationContract
          && builtins.isAttrs site.provenance.originalInputs.communicationContract
        then
          site.provenance.originalInputs.communicationContract
        else if site ? communicationContract && builtins.isAttrs site.communicationContract then
          site.communicationContract
        else
          { };
    in
    {
      relations = communicationContract.relations or [ ];
      services = communicationContract.services or [ ];
      trafficTypes = communicationContract.trafficTypes or [ ];
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
      t0 = firstOrNull ((site.domains or { }).tenants or [ ]);

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

      aggregationMode =
        if site ? aggregation && builtins.isAttrs site.aggregation && site.aggregation ? mode then
          site.aggregation.mode
        else
          "none";

      unitNames = lib.unique (
        (if site ? units && builtins.isAttrs site.units then builtins.attrNames site.units else [ ])
        ++ (if site ? nodes && builtins.isAttrs site.nodes then builtins.attrNames site.nodes else [ ])
        ++ (rolesResult.traversal.chain or [ ])
        ++ builtins.attrNames (rolesResult.traversal.inferred or { })
      );

      nodes = lib.listToAttrs (
        map (u: {
          name = toString u;
          value =
            let
              unitName = toString u;
              base = nodeFromSite site unitName;
              attachedNetworks = tenantNetworksForUnit site unitName;
            in
            base
            // {
              role = rolesResult.roleFromInput unitName;
              containers = base.containers or [ "default" ];
            }
            // lib.optionalAttrs (attachedNetworks != { }) {
              networks = attachedNetworks;
            };
        }) unitNames
      );

      p2pLinks = p2pAlloc.alloc {
        site = {
          p2p-pool = p2pPool;
          links = lib.filter (p: builtins.isList p && builtins.length p == 2) ordering;
          inherit nodes;
          domains = site.domains or { };
        };
      };

      coreNodeNames = lib.sort (a: b: a < b) (
        map toString (lib.filter (u: rolesResult.roleFromInput u == "core") unitNames)
      );

      _ =
        if coreNodeNames == [ ] then throw "network-solver: missing core unit for coreNodeNames" else true;

      policyNodeName = if rolesResult.policyUnit == null then null else toString rolesResult.policyUnit;

      upstreamSelectorNodeName = firstOrNull (
        lib.sort (a: b: a < b) (
          lib.filter (u: rolesResult.roleFromInput u == "upstream-selector") unitNames
        )
      );

      routed0 = topoResolve (
        enforcementResult
        // {
          inherit
            siteName
            tenantV4Base
            ulaPrefix
            enterprise
            siteId
            coreNodeNames
            policyNodeName
            upstreamSelectorNodeName
            ;
          uplinkCoreNames = wanResult.uplinkCores or [ ];
          uplinkNames = wanResult.uplinkNames or [ ];
          p2p-pool = p2pPool;
          routerLoopbacks = site.routerLoopbacks or { };
          aggregation = {
            mode = aggregationMode;
          };
          inherit nodes;
          links = p2pLinks // (wanResult.wanLinks or { }) // (site.links or { });
        }
      );

      routed1 = routed0 // {
        nodes = lib.mapAttrs (
          _: node:
          node
          // {
            interfaces = lib.mapAttrs (_: normalizeRoutes) (node.interfaces or { });
          }
        ) (routed0.nodes or { });
      };

      routed =
        builtins.removeAttrs routed1 [
          "_enforcement"
          "_nat"
          "_loopbackResolution"
          "compilerIR"
          "p2p-pool"
          "tenantV4Base"
          "ulaPrefix"
        ]
        // {
          inherit enterprise siteId;
          siteName = routed1.siteName or siteName;
          coreNodeNames = routed1.coreNodeNames or coreNodeNames;
          policyNodeName = routed1.policyNodeName or policyNodeName;
          upstreamSelectorNodeName = routed1.upstreamSelectorNodeName or upstreamSelectorNodeName;
          uplinkCoreNames = routed1.uplinkCoreNames or (wanResult.uplinkCores or [ ]);
          uplinkNames = routed1.uplinkNames or (wanResult.uplinkNames or [ ]);
          routerLoopbacks = routed1.routerLoopbacks or (site.routerLoopbacks or { });
          policyIntent = policyIntentFromSite site;
          policy = {
            owner = routed1._enforcement.owner or null;
            rules = [ ];
            validExternalRefs = routed1._enforcement.validExternalRefs or [ ];
          };
          aggregation = {
            mode =
              if routed1 ? aggregation && builtins.isAttrs routed1.aggregation && routed1.aggregation ? mode then
                routed1.aggregation.mode
              else
                aggregationMode;
          };
        };
    in
    routed;
}
