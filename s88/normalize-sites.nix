{ lib }:
{ config }:

let
  attrs = import ./normalize-sites/attrs.nix { inherit lib; };
  inherit (attrs) getAttrPathOr mergeAttrs;

  mkEmptySite = import ./normalize-sites/default-site.nix;
  domainsLib = import ./normalize-sites/domains.nix {
    inherit lib getAttrPathOr mergeAttrs;
  };
  shapeLib = import ./normalize-sites/site-shape.nix {
    inherit (attrs) getAttrPathOr hasAttrPath;
  };
  inherit (domainsLib) normalizeDomains normalizePolicy;
  inherit (shapeLib)
    normalizeAddressPools
    normalizeCommunicationContract
    normalizeLinks
    normalizeNodes
    normalizeTopology
    siteAttachmentsFromTopology
    siteCoreNodeNamesFromTopology
    ;

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
