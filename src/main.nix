{ lib, ... }:
{ input }:

let
  config = input;

  hasAttrPath =
    path: set:
    if path == [ ] then
      true
    else
      let
        key = builtins.head path;
      in
      builtins.isAttrs set && builtins.hasAttr key set && hasAttrPath (builtins.tail path) set.${key};

  getAttrPathOr =
    path: default: set:
    if path == [ ] then
      set
    else
      let
        key = builtins.head path;
      in
      if builtins.isAttrs set && builtins.hasAttr key set then
        getAttrPathOr (builtins.tail path) default set.${key}
      else
        default;

  mergeAttrs =
    left: right:
    if builtins.isAttrs left && builtins.isAttrs right then lib.recursiveUpdate left right else right;

  attrsetIsNonEmpty = value: builtins.isAttrs value && (builtins.attrNames value) != [ ];

  mkEmptySite = {
    addressPools = {
      local = { };
      p2p = { };
    };
    attachments = [ ];
    communicationContract = {
      interfaceTags = { };
      allowedRelations = [ ];
      services = [ ];
      trafficTypes = [ ];
    };
    coreNodeNames = [ ];
    domains = {
      externals = [ ];
      tenants = [ ];
    };
    links = { };
    nodes = { };
    topology = {
      nodes = { };
      links = [ ];
    };
    transport = { };
    transit = { };
  };

  upstreamOriginalInputs = getAttrPathOr [ "meta" "provenance" "originalInputs" ] { } config;

  explicitSitesByEnterprise =
    if config ? sites then
      config.sites
    else if config ? enterprise then
      builtins.mapAttrs (_: enterpriseValue: enterpriseValue.site or { }) config.enterprise
    else
      { };

  allEnterpriseNames = lib.unique (
    (builtins.attrNames explicitSitesByEnterprise) ++ (builtins.attrNames upstreamOriginalInputs)
  );

  mergeSitesForEnterprise =
    enterpriseName:
    let
      explicit = explicitSitesByEnterprise.${enterpriseName} or { };
      original = upstreamOriginalInputs.${enterpriseName} or { };
      siteNames = lib.unique ((builtins.attrNames explicit) ++ (builtins.attrNames original));
    in
    builtins.listToAttrs (
      builtins.map (siteId: {
        name = siteId;
        value = mergeAttrs (original.${siteId} or { }) (explicit.${siteId} or { });
      }) siteNames
    );

  rawSitesByEnterprise = builtins.listToAttrs (
    builtins.map (enterpriseName: {
      name = enterpriseName;
      value = mergeSitesForEnterprise enterpriseName;
    }) allEnterpriseNames
  );

  siteTenantsFromOwnership =
    site:
    let
      prefixes = getAttrPathOr [ "ownership" "prefixes" ] [ ] site;
      isTenantPrefix = prefix: (prefix.kind or null) == "tenant";
      mkTenant =
        prefix:
        {
          name = prefix.name;
        }
        // lib.optionalAttrs (prefix ? ipv4) { ipv4 = prefix.ipv4; }
        // lib.optionalAttrs (prefix ? ipv6) { ipv6 = prefix.ipv6; };
    in
    builtins.map mkTenant (builtins.filter isTenantPrefix prefixes);

  siteExternalsFromCommunicationContract =
    site:
    let
      tags = getAttrPathOr [ "communicationContract" "interfaceTags" ] { } site;
      tagNames = builtins.attrNames tags;
      externalNames = builtins.map (tagName: lib.removePrefix "external-" tagName) (
        builtins.filter (tagName: lib.hasPrefix "external-" tagName) tagNames
      );
    in
    builtins.map (name: {
      kind = "external";
      inherit name;
    }) externalNames;

  siteAttachmentsFromTopology =
    site:
    let
      nodes = getAttrPathOr [ "topology" "nodes" ] { } site;
      nodeNames = builtins.attrNames nodes;
    in
    builtins.concatLists (
      builtins.map (
        nodeName:
        builtins.map (attachment: attachment // { unit = nodeName; }) (nodes.${nodeName}.attachments or [ ])
      ) nodeNames
    );

  siteCoreNodeNamesFromTopology =
    site:
    let
      nodes = getAttrPathOr [ "topology" "nodes" ] { } site;
      nodeNames = builtins.attrNames nodes;
    in
    builtins.filter (nodeName: (nodes.${nodeName}.role or null) == "core") nodeNames;

  normalizeCommunicationContract =
    site:
    let
      cc = site.communicationContract or { };
    in
    {
      interfaceTags = cc.interfaceTags or { };
      allowedRelations =
        if cc ? allowedRelations then
          cc.allowedRelations
        else if cc ? relations then
          cc.relations
        else
          [ ];
      services = cc.services or [ ];
      trafficTypes = cc.trafficTypes or [ ];
    };

  normalizeAddressPools =
    site:
    let
      explicitAddressPools =
        if site ? addressPools && builtins.isAttrs site.addressPools then site.addressPools else { };

      explicitLocal =
        if explicitAddressPools ? local && attrsetIsNonEmpty explicitAddressPools.local then
          explicitAddressPools.local
        else
          null;

      explicitP2p =
        if explicitAddressPools ? p2p && attrsetIsNonEmpty explicitAddressPools.p2p then
          explicitAddressPools.p2p
        else
          null;
    in
    {
      local =
        if explicitLocal != null then
          explicitLocal
        else if hasAttrPath [ "pools" "loopback" ] site then
          site.pools.loopback
        else if hasAttrPath [ "pools" "local" ] site then
          site.pools.local
        else
          { };
      p2p =
        if explicitP2p != null then
          explicitP2p
        else if hasAttrPath [ "pools" "p2p" ] site then
          site.pools.p2p
        else
          { };
    };

  normalizeDomains =
    site:
    let
      explicitDomains = site.domains or { };
      explicitTenants = explicitDomains.tenants or [ ];
      derivedTenants = if explicitTenants != [ ] then explicitTenants else siteTenantsFromOwnership site;

      explicitExternals = explicitDomains.externals or [ ];
      derivedExternals =
        if explicitExternals != [ ] then explicitExternals else siteExternalsFromCommunicationContract site;
    in
    explicitDomains
    // {
      tenants = derivedTenants;
      externals = derivedExternals;
    };

  normalizeTopology =
    site:
    let
      topology = site.topology or { };
    in
    {
      nodes = topology.nodes or { };
      links = topology.links or [ ];
    };

  normalizeLinks = site: if site ? links then site.links else { };

  normalizeNodes = site: if site ? nodes then site.nodes else { };

  normalizeSite =
    enterpriseName: siteId: site:
    let
      merged = mkEmptySite // site;
      addressPools = normalizeAddressPools merged;
      topology = normalizeTopology merged;
      nodes = normalizeNodes merged;
      links = normalizeLinks merged;
      communicationContract = normalizeCommunicationContract merged;
      domains = normalizeDomains merged;
      attachments =
        if merged ? attachments && merged.attachments != [ ] then
          merged.attachments
        else
          siteAttachmentsFromTopology merged;
      coreNodeNames =
        if merged ? coreNodeNames && merged.coreNodeNames != [ ] then
          merged.coreNodeNames
        else
          siteCoreNodeNamesFromTopology merged;
    in
    merged
    // {
      enterprise = merged.enterprise or enterpriseName;
      siteId = merged.siteId or siteId;
      addressPools = addressPools;
      attachments = attachments;
      communicationContract = communicationContract;
      coreNodeNames = coreNodeNames;
      domains = domains;
      topology = topology;
      nodes = nodes;
      links = links;
      transport = merged.transport or { };
      transit = (merged.transit or { }) // {
        ordering = if merged.transit ? ordering then merged.transit.ordering else topology.links;
      };
    };

  normalizedSitesByEnterprise = builtins.mapAttrs (
    enterpriseName: sites:
    builtins.mapAttrs (siteId: site: normalizeSite enterpriseName siteId site) sites
  ) rawSitesByEnterprise;

  solver = import ./solver { inherit lib; };

  solverResultByEnterprise = builtins.mapAttrs (
    enterpriseName: sites:
    solver {
      enterprise = enterpriseName;
      inherit sites;
    }
  ) normalizedSitesByEnterprise;

  extractSolvedSites =
    enterpriseName: result:
    if builtins.isAttrs result && result ? site then
      result.site
    else if
      builtins.isAttrs result && result ? enterprise && builtins.hasAttr enterpriseName result.enterprise
    then
      let
        enterpriseResult = result.enterprise.${enterpriseName};
      in
      if builtins.isAttrs enterpriseResult && enterpriseResult ? site then
        enterpriseResult.site
      else
        enterpriseResult
    else
      result;

  solvedSitesByEnterprise = builtins.mapAttrs extractSolvedSites solverResultByEnterprise;

  enterpriseNames = builtins.attrNames solverResultByEnterprise;

  firstEnterpriseName = if enterpriseNames == [ ] then null else builtins.head enterpriseNames;

  firstSolverResult =
    if firstEnterpriseName == null then { } else solverResultByEnterprise.${firstEnterpriseName};

  inheritedMetaRaw =
    if builtins.isAttrs firstSolverResult && firstSolverResult ? meta then
      firstSolverResult.meta
    else
      { };

  inheritedMeta = builtins.removeAttrs inheritedMetaRaw [ "solver" ];

  contracts = {
    input = {
      site = {
        addressPools = {
          local = "required";
          p2p = "required";
        };
        domains = {
          tenants = "canonical";
        };
        topology = {
          links = {
            directed = true;
            shape = "node-pairs";
            example = [
              [
                "<from-node>"
                "<to-node>"
              ]
            ];
          };
        };
      };
    };

    normalization = {
      site = {
        addressPools = {
          derived = true;
          source = "site.addressPools or site.pools";
        };
        domains = {
          tenants = {
            derived = true;
            source = "site.domains.tenants or site.ownership.prefixes[kind=tenant]";
          };
          externals = {
            derived = true;
            source = "site.domains.externals or communicationContract.interfaceTags[external-*]";
          };
        };
        attachments = {
          derived = true;
          source = "site.attachments or site.topology.nodes.*.attachments";
        };
        transit = {
          nodePairOrdering = {
            derived = true;
            field = "site.transit.ordering";
            shape = "node-pairs";
            source = "site.topology.links";
            stage = "internal-normalized";
          };
        };
      };
    };

    output = {
      link = {
        id = "link::<siteName>::<linkName>";
      };
      transit = {
        adjacencies = {
          idField = "id";
          endpoint = {
            unit = "required";
            local = {
              ipv4 = "required";
              ipv6 = "optional";
            };
          };
        };
        ordering = {
          field = "enterprise.<enterprise>.site.<site>.transit.ordering";
          shape = "stable-link-ids";
          source = "resolved internal transit node-pair ordering against realized p2p links";
        };
      };
    };
  };
in
{
  enterprise = builtins.mapAttrs (_: sites: { site = sites; }) solvedSitesByEnterprise;

  meta = inheritedMeta // {
    networkForwardingModel = (inheritedMeta.networkForwardingModel or { }) // {
      name = "network-forwarding-model";
      schemaVersion = 6;
      inherit contracts;
    };
  };
}
