{ lib, self ? { outPath = ./.; }, ... }:
{ config }:

let
  attrs = import ./attrs.nix { inherit lib self; };
  inherit (attrs) getAttrPathOr mergeAttrs;

  mkEmptySite = import ./empty-site.nix;
  domainsLib = import ./domains.nix {
    inherit lib getAttrPathOr mergeAttrs;
  };
  shapeLib = import ./shape.nix {
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
      builtins.map
        (siteId:
          let
            explicitSite = explicit.${siteId} or { };
            mergedSite = mergeAttrs (original.${siteId} or { }) explicitSite;
          in
          {
            name = siteId;
            value = mergedSite // {
              # FS-982-HDS-010-SDS-010-SMS-120: hostManagement is behavior
              # authority emitted by the compiler. The originalInputs copy is
              # provenance only and must never reintroduce an atom omitted by
              # the explicit compiler output.
              hostManagement = explicitSite.hostManagement or null;
            };
          })
        siteNames
    );

  rawSitesByEnterprise = builtins.listToAttrs (
    builtins.map
      (enterpriseName: {
        name = enterpriseName;
        value = mergeSitesForEnterprise enterpriseName;
      })
      allEnterpriseNames
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

      # FS-540: Preserve address-free DNS intent contracts through the compiler
      # pipeline so the CPM can emit named-dns-binding and local-dns-sharing
      # runtime targets. The original intent keys are recursiveDnsIntent and
      # localDnsSharingIntent; the CPM expects them nested under dns.recursive
      # and dns.localSharing.
      mergedDns = merged.dns or { };
      dns = mergedDns // (
        if merged ? recursiveDnsIntent || merged ? localDnsSharingIntent then
          { }
          // lib.optionalAttrs (merged ? recursiveDnsIntent) { recursive = merged.recursiveDnsIntent; }
          // lib.optionalAttrs (merged ? localDnsSharingIntent) { localSharing = merged.localDnsSharingIntent; }
        else
          { }
      );
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
      hostNatIngress = (merged.topology.hostNatIngress or (merged.hostNatIngress or { }));
      nodes = nodes;
      links = links;
      transport = merged.transport or { };
      transit = (merged.transit or { }) // {
        ordering = if merged.transit ? ordering then merged.transit.ordering
                   else if merged ? transit && builtins.isAttrs merged.transit && merged.transit ? links then merged.transit.links
                   else topology.links;
      };
    }
    // lib.optionalAttrs (dns != { }) { inherit dns; };

  normalizedSitesByEnterprise = builtins.mapAttrs
    (
      enterpriseName: sites:
        builtins.mapAttrs (siteId: site: normalizeSite enterpriseName siteId site) sites
    )
    rawSitesByEnterprise;

in
normalizedSitesByEnterprise
