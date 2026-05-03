{ lib }:
{ config }:

let
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

  mkEmptySite = {
    addressPools = {
      local = { };
      p2p = { };
    };
    attachments = [ ];
    communicationContract = {
      allowedRelations = [ ];
      services = [ ];
      trafficTypes = [ ];
    };
    policy = {
      interfaceTags = { };
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
        // lib.optionalAttrs (prefix ? ipv6) { ipv6 = prefix.ipv6; }
        // lib.optionalAttrs (prefix ? ra6Prefixes) { ra6Prefixes = prefix.ra6Prefixes; };
    in
    builtins.map mkTenant (builtins.filter isTenantPrefix prefixes);

  rawPolicyInterfaceTags =
    site:
    if
      site ? policy
      && builtins.isAttrs site.policy
      && site.policy ? interfaceTags
      && builtins.isAttrs site.policy.interfaceTags
    then
      site.policy.interfaceTags
    else
      { };

  siteExternalsFromPolicy =
    site:
    let
      tags = rawPolicyInterfaceTags site;
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

  siteInterfaceTagsFromAttachments =
    attachments:
    builtins.foldl' (
      acc: attachment:
      if !(attachment ? name) || attachment.name == null then
        acc
      else
        let
          tagName = attachment.name;
          existing = acc.${tagName} or { };
        in
        acc
        // {
          "${tagName}" = mergeAttrs existing {
            attachments = (existing.attachments or [ ]) ++ [
              attachment
            ];
          };
        }
    ) { } attachments;

  siteInterfaceTagsFromDomains =
    domains:
    let
      tenantEntries = builtins.map (tenant: {
        name = tenant.name;
        value = {
          domains = [
            (
              {
                kind = "tenant";
                name = tenant.name;
              }
              // lib.optionalAttrs (tenant ? ipv4) { ipv4 = tenant.ipv4; }
              // lib.optionalAttrs (tenant ? ipv6) { ipv6 = tenant.ipv6; }
            )
          ];
        };
      }) (domains.tenants or [ ]);

      externalEntries = builtins.map (external: {
        name = "external-${external.name}";
        value = {
          domains = [
            (
              {
                kind = external.kind or "external";
                name = external.name;
              }
              // lib.optionalAttrs (external ? ipv4) { ipv4 = external.ipv4; }
              // lib.optionalAttrs (external ? ipv6) { ipv6 = external.ipv6; }
            )
          ];
        };
      }) (domains.externals or [ ]);
    in
    builtins.listToAttrs (tenantEntries ++ externalEntries);

  normalizePolicy =
    {
      site,
      domains,
      attachments,
    }:
    let
      explicitPolicy = if site ? policy && builtins.isAttrs site.policy then site.policy else { };
      explicitInterfaceTags =
        if explicitPolicy ? interfaceTags && builtins.isAttrs explicitPolicy.interfaceTags then
          explicitPolicy.interfaceTags
        else
          { };
      derivedInterfaceTags = mergeAttrs (siteInterfaceTagsFromDomains domains) (
        siteInterfaceTagsFromAttachments attachments
      );
    in
    explicitPolicy
    // {
      interfaceTags = mergeAttrs derivedInterfaceTags explicitInterfaceTags;
    };

  normalizeCommunicationContract =
    site:
    let
      cc = site.communicationContract or { };
    in
    {
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
      explicitAddressPools = site.addressPools or null;
      explicitLocal = if explicitAddressPools == null then null else explicitAddressPools.local or null;
      explicitP2p = if explicitAddressPools == null then null else explicitAddressPools.p2p or null;

      derivedLocal =
        if hasAttrPath [ "pools" "loopback" ] site then
          site.pools.loopback
        else if hasAttrPath [ "pools" "local" ] site then
          site.pools.local
        else
          { };

      derivedP2p = if hasAttrPath [ "pools" "p2p" ] site then site.pools.p2p else { };
    in
    {
      local = if explicitLocal != null && explicitLocal != { } then explicitLocal else derivedLocal;
      p2p = if explicitP2p != null && explicitP2p != { } then explicitP2p else derivedP2p;
    };

  normalizeDomains =
    site:
    let
      explicitDomains = site.domains or { };
      explicitTenants = explicitDomains.tenants or [ ];
      derivedTenants = if explicitTenants != [ ] then explicitTenants else siteTenantsFromOwnership site;

      explicitExternals = explicitDomains.externals or [ ];
      derivedExternals =
        if explicitExternals != [ ] then explicitExternals else siteExternalsFromPolicy site;
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
      raw = site;
      merged = mkEmptySite // raw;
      addressPools = normalizeAddressPools raw;
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
      policy = normalizePolicy {
        site = merged;
        inherit domains attachments;
      };
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
      policy = policy;
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

in
normalizedSitesByEnterprise
