{ lib, self ? { outPath = ./.; }, ... }:

let
  utils = import (self.outPath + "/implementation/lib/s88-support") { inherit lib self; };

  normalizeTenantsFromRaw =
    tenants0:
    if builtins.isList tenants0 then
      tenants0
    else if builtins.isAttrs tenants0 then
      builtins.attrValues
        (
          lib.mapAttrs
            (
              name: v:
              if builtins.isAttrs v then
                v // { name = toString (v.name or name); }
              else
                {
                  name = toString name;
                }
            )
            tenants0
        )
    else
      [ ];

  normalizeTenants =
    site:
    lib.filter (t: builtins.isAttrs t && (t.name or null) != null) (
      normalizeTenantsFromRaw (
        if site ? tenants && site.tenants != [ ] then site.tenants else ((site.domains or { }).tenants or [ ])
      )
    );

  tenantCatalog =
    site:
    builtins.listToAttrs (
      map
        (t: {
          name = toString t.name;
          value = {
            kind = t.kind or "tenant";
            name = toString t.name;
            ipv4 = t.ipv4 or null;
            ipv6 = t.ipv6 or null;
            ra6Prefixes = t.ra6Prefixes or [ ];
            routedPrefixes = t.routedPrefixes or [ ];
          };
        })
        (normalizeTenants site)
    );

  siteContext =
    site:
    let
      normalizedTenants = normalizeTenants site;
      catalog = builtins.listToAttrs (
        map
          (t: {
            name = toString t.name;
            value = {
              kind = t.kind or "tenant";
              name = toString t.name;
              ipv4 = t.ipv4 or null;
              ipv6 = t.ipv6 or null;
              ra6Prefixes = t.ra6Prefixes or [ ];
              routedPrefixes = t.routedPrefixes or [ ];
            };
          })
          normalizedTenants
      );
      tenantNamesByUnit =
        builtins.foldl'
          (
            acc: attachment:
              if !(builtins.isAttrs attachment) then
                acc
              else
                let
                  unit = utils.unitRefOfAttachment attachment;
                  names = tenantNameFromValue attachment;
                in
                if unit == null || names == [ ] then
                  acc
                else
                  acc // { "${unit}" = lib.unique ((acc.${unit} or [ ]) ++ names); }
          )
          { }
          (utils.attachmentsOf site);
    in
    {
      inherit catalog normalizedTenants tenantNamesByUnit;
    };

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
    explicitTenantNamesForUnitWithContext (siteContext site) unitName;

  explicitTenantNamesForUnitWithContext =
    context: unitName:
      context.tenantNamesByUnit.${toString unitName} or [ ];

  tenantNetworksForUnit =
    site: unitName:
    tenantNetworksForUnitWithContext (siteContext site) unitName;

  tenantNetworksForUnitWithContext =
    context: unitName:
    let
      names = explicitTenantNamesForUnitWithContext context unitName;
      unknown = lib.filter (name: !(context.catalog ? "${name}")) names;

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
        map
          (name: {
            name = toString name;
            value = context.catalog.${name};
          })
          names
      )
    );

in
{
  inherit
    normalizeTenantsFromRaw
    normalizeTenants
    tenantCatalog
    siteContext
    tenantNameFromValue
    explicitTenantNamesForUnit
    explicitTenantNamesForUnitWithContext
    tenantNetworksForUnit
    tenantNetworksForUnitWithContext
    ;
}
