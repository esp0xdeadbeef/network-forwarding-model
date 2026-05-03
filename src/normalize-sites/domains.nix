{
  lib,
  getAttrPathOr,
  mergeAttrs,
}:

let
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
        // lib.optionalAttrs (prefix ? ra6Prefixes) { ra6Prefixes = prefix.ra6Prefixes; }
        // lib.optionalAttrs (prefix ? routedPrefixes) { routedPrefixes = prefix.routedPrefixes; };
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
              // lib.optionalAttrs (tenant ? routedPrefixes) { routedPrefixes = tenant.routedPrefixes; }
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

in
{
  inherit
    normalizeDomains
    normalizePolicy
    ;
}
