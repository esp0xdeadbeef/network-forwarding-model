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
        // lib.optionalAttrs (prefix ? ipv6) { ipv6 = prefix.ipv6; };
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

  solver = import ./solver { inherit lib; };

  solverResultByEnterprise = builtins.mapAttrs (
    enterpriseName: sites:
    solver {
      enterprise = enterpriseName;
      inherit sites;
      allSites = normalizedSitesByEnterprise;
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

  flatSolvedSites = builtins.foldl' (
    acc: enterpriseName:
    let
      enterpriseSites = solvedSitesByEnterprise.${enterpriseName} or { };
      siteNames = builtins.attrNames enterpriseSites;
    in
    acc
    // builtins.listToAttrs (
      map (siteId: {
        name = "${enterpriseName}.${siteId}";
        value = (enterpriseSites.${siteId}) // {
          enterprise = (enterpriseSites.${siteId}.enterprise or enterpriseName);
          siteId = (enterpriseSites.${siteId}.siteId or siteId);
          siteName = (enterpriseSites.${siteId}.siteName or "${enterpriseName}.${siteId}");
        };
      }) siteNames
    )
  ) { } (builtins.attrNames solvedSitesByEnterprise);

  invariants = import ../lib/fabric/invariants { inherit lib; };

  _siteInvariantChecks = builtins.deepSeq (builtins.attrValues (
    builtins.mapAttrs (_: site: invariants.checkSite { inherit site; }) flatSolvedSites
  )) true;

  _globalInvariantChecks = invariants.checkAll { sites = flatSolvedSites; };

  overlayTraversalWarnings =
    let
      overlayWarningsForSite =
        siteKey: site:
        let
          overlayNames = builtins.attrNames (site.overlayReachability or { });
          linkNames = builtins.attrNames (site.links or { });
          hasAccessLaneForOverlay =
            overlayName:
            builtins.any (
              linkName: builtins.match ".*--access-.+--uplink-${overlayName}" linkName != null
            ) linkNames;
          overlayHasTermination =
            overlayName: ((site.overlayReachability.${overlayName}.terminateOn or [ ]) != [ ]);
        in
        lib.concatMap (
          overlayName:
          if overlayHasTermination overlayName && !(hasAccessLaneForOverlay overlayName) then
            [
              "network-forwarding-model: ${siteKey}: overlay '${overlayName}' terminates on core node(s) but has no access-specific uplink lane; Nebula overlay cores must be reached through access/policy traversal, so add an allowed relation from the intended access tenant(s) to external '${overlayName}'"
            ]
          else
            [ ]
        ) overlayNames;
    in
    lib.concatMap (siteKey: overlayWarningsForSite siteKey flatSolvedSites.${siteKey}) (
      builtins.attrNames flatSolvedSites
    );

  enterpriseNames = builtins.attrNames solverResultByEnterprise;

  firstEnterpriseName = if enterpriseNames == [ ] then null else builtins.head enterpriseNames;

  firstSolverResult =
    if firstEnterpriseName == null then { } else solverResultByEnterprise.${firstEnterpriseName};

  inheritedMeta =
    if builtins.isAttrs firstSolverResult && firstSolverResult ? meta then
      firstSolverResult.meta
    else
      { };

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
        forwardingSemantics = {
          nodes = "accepted-as-role-hints";
          coreNodeNames = "accepted-as-role-hints";
          policyNodeName = "accepted-as-role-hints";
          upstreamSelectorNodeName = "accepted-as-role-hints";
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
            source = "site.domains.externals or site.policy.interfaceTags[external-*]";
          };
        };
        attachments = {
          derived = true;
          source = "site.attachments or site.topology.nodes.*.attachments";
        };
        roles = {
          derived = true;
          source = "site.topology.nodes.*.role or site.nodes.*.role or site.units.*.role or site.forwardingSemantics";
        };
        policy = {
          interfaceTags = {
            derived = true;
            source = "site.policy.interfaceTags merged with site.attachments and site.domains";
          };
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
      node = {
        forwarding = {
          functions = "explicit";
          traversal = {
            participates = "explicit";
            chainIndex = "explicit";
            incoming = "explicit";
            outgoing = "explicit";
          };
          responsibilities = {
            accessTermination = "explicit";
            policyEnforcement = "explicit";
            transitForwarding = "explicit";
          };
          authority = {
            attachedPrefixRouting = "explicit";
            transitRouting = "explicit";
            upstreamSelection = "explicit";
          };
        };
        egress = {
          authority = "explicit";
          upstreamSelection = "explicit";
          exitEligible = "explicit";
          wanInterfaces = "explicit";
          uplinkNames = "explicit";
        };
      };
      route = {
        intent = {
          field = "intent.kind";
          values = [
            "connected-reachability"
            "internal-reachability"
            "overlay-reachability"
            "uplink-learned-reachability"
            "default-reachability"
          ];
        };
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

  result = {
    enterprise = builtins.mapAttrs (_: sites: { site = sites; }) solvedSitesByEnterprise;

    meta = inheritedMeta // {
      networkForwardingModel = (inheritedMeta.networkForwardingModel or { }) // {
        name = "network-forwarding-model";
        schemaVersion = 9;
        inherit contracts;
        warningMessages = lib.unique (
          (inheritedMeta.networkForwardingModel.warningMessages or [ ]) ++ overlayTraversalWarnings
        );
      };
    };
  };
in
builtins.seq _siteInvariantChecks (builtins.seq _globalInvariantChecks result)
