{ lib }:

let
  utils = import ../../../util { inherit lib; };

  normalizeTenantsFromRaw =
    tenants0:
    if builtins.isList tenants0 then
      tenants0
    else if builtins.isAttrs tenants0 then
      builtins.attrValues (
        lib.mapAttrs (
          name: v:
          if builtins.isAttrs v then
            v // { name = toString (v.name or name); }
          else
            {
              name = toString name;
            }
        ) tenants0
      )
    else
      [ ];

  normalizeTenants =
    site:
    lib.filter (t: builtins.isAttrs t && (t.name or null) != null) (
      normalizeTenantsFromRaw ((site.domains or { }).tenants or [ ])
    );

  tenantCatalog =
    site:
    builtins.listToAttrs (
      map (t: {
        name = toString t.name;
        value = {
          kind = t.kind or "tenant";
          name = toString t.name;
          ipv4 = t.ipv4 or null;
          ipv6 = t.ipv6 or null;
        };
      }) (normalizeTenants site)
    );

  tenantNameFromValue =
    x:
    if x == null then
      [ ]
    else if builtins.isString x then
      [ (toString x) ]
    else if builtins.isList x then
      lib.unique (lib.concatMap tenantNameFromValue x)
    else if builtins.isAttrs x then
      let
        direct = lib.filter (v: v != null) [
          (if (x.kind or null) == "tenant" && (x.name or null) != null then toString x.name else null)
          (if (x.tenant or null) != null then toString x.tenant else null)
          (if (x.tenantName or null) != null then toString x.tenantName else null)
        ];

        nested = lib.concatMap tenantNameFromValue (
          lib.filter (v: v != null) [
            (x.segment or null)
            (x.subject or null)
            (x.ingressSubject or null)
            (x.from or null)
            (x.to or null)
          ]
        );
      in
      lib.unique (direct ++ nested)
    else
      [ ];

  explicitTenantNamesForUnit =
    site: unitName:
    let
      attachments = utils.attachmentsOf site;
      forUnit = lib.filter (a: (utils.unitRefOfAttachment a) == unitName) attachments;
    in
    lib.unique (lib.concatMap tenantNameFromValue forUnit);

  tenantNetworksForUnit =
    site: unitName:
    let
      catalog = tenantCatalog site;
      names = explicitTenantNamesForUnit site unitName;
      unknown = lib.filter (name: !(catalog ? "${name}")) names;

      _known =
        if unknown == [ ] then
          true
        else
          throw ''
            network-forwarding-model: attachment references unknown tenant(s)

            unit: ${toString unitName}
            tenants: ${builtins.toJSON unknown}
          '';
    in
    builtins.seq _known (
      builtins.listToAttrs (
        map (name: {
          name = toString name;
          value = catalog.${name};
        }) names
      )
    );

  tenantPrefixesOfSite =
    site:
    let
      tenants = normalizeTenants site;

      ipv4 = lib.unique (
        lib.filter (x: x != null) (
          map (t: if (t.ipv4 or null) != null then toString t.ipv4 else null) tenants
        )
      );

      ipv6 = lib.unique (
        lib.filter (x: x != null) (
          map (t: if (t.ipv6 or null) != null then toString t.ipv6 else null) tenants
        )
      );
    in
    {
      inherit ipv4 ipv6;
    };

  tenantPrefixEntriesFromDomains =
    domains:
    let
      tenants = lib.filter (t: builtins.isAttrs t && (t.name or null) != null) (
        normalizeTenantsFromRaw (domains.tenants or [ ])
      );
    in
    lib.concatMap (
      t:
      lib.flatten [
        (lib.optional ((t.ipv4 or null) != null) {
          family = 4;
          cidr = toString t.ipv4;
          label = "domains.tenants.${toString t.name}.ipv4";
        })
        (lib.optional ((t.ipv6 or null) != null) {
          family = 6;
          cidr = toString t.ipv6;
          label = "domains.tenants.${toString t.name}.ipv6";
        })
      ]
    ) tenants;

in
{
  inherit
    normalizeTenants
    tenantCatalog
    tenantNameFromValue
    explicitTenantNamesForUnit
    tenantNetworksForUnit
    tenantPrefixesOfSite
    tenantPrefixEntriesFromDomains
    ;
}
