{ lib, self ? { outPath = ./.; }, ... }:

let
  tenants = import ./tenants.nix { inherit lib self; };
  prefix = import (self.outPath + "/implementation/lib/model/prefix-utils.nix") { inherit lib self; };
in
{
  prefixesOfSite =
    site:
    let
      normalizedTenants = tenants.normalizeTenants site;

      ipv4 = lib.unique (
        lib.filter (x: x != null) (
          map (t: if (t.ipv4 or null) != null then toString t.ipv4 else null) normalizedTenants
        )
      );

      ipv6 = lib.unique (
        lib.filter (x: x != null) (
          (map (t: if (t.ipv6 or null) != null then toString t.ipv6 else null) normalizedTenants)
          ++ (lib.concatMap (t: map toString (t.ra6Prefixes or [ ])) normalizedTenants)
          ++ (lib.concatMap
            (
              t:
              map (prefix: toString prefix.ipv6) (
                lib.filter (prefix: builtins.isAttrs prefix && (prefix.ipv6 or null) != null) (t.routedPrefixes or [ ])
              )
            )
            normalizedTenants)
        )
      );
    in
    {
      inherit ipv4 ipv6;
    };

  entriesFromDomains =
    domains:
    let
      normalizedTenants = lib.filter (t: builtins.isAttrs t && (t.name or null) != null) (
        tenants.normalizeTenantsFromRaw (domains.tenants or [ ])
      );
    in
    lib.concatMap
      (
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
          (map
            (prefix: {
              family = 6;
              cidr = toString prefix;
              label = "domains.tenants.${toString t.name}.ra6Prefixes";
            })
            (t.ra6Prefixes or [ ]))
        ]
      )
      normalizedTenants;

  # Runtime (source-file driven) tenant prefix entries of a site. The authority
  # class comes from the model's prefix-utils classification, never from a local
  # re-derivation: FS-171 makes this the owning layer for tenant prefix facts and
  # FS-350-SMS-030 distinguishes a host-only provider address (an overlay
  # participant address, not tenant-prefix authority) from a routed client
  # prefix that legitimately carries overlay reachability.
  runtimePrefixEntriesOfSite =
    site:
    let
      normalizedTenants = tenants.normalizeTenants site;
    in
    lib.concatMap
      (
        t:
        lib.concatMap
          (
            p:
            let
              family = prefix.routedPrefixFamily p;
              defaultLength = prefix.defaultRoutedPrefixLengthFor family;
            in
            lib.optional
              (builtins.isAttrs p && builtins.isString (p.sourceFile or null) && (p.sourceFile or "") != "")
              {
                inherit family;
                inherit (p) sourceFile;
                tenantName = toString t.name;
                authorityClass = prefix.runtimeAuthorityClass p;
                prefixName = p.name or null;
                delegatedPrefixLength = p.delegatedPrefixLength or defaultLength;
                perTenantPrefixLength = p.perTenantPrefixLength or defaultLength;
                slot = p.slot or 0;
                prefixPostfix = p.prefixPostfix or null;
              }
          )
          (lib.filter builtins.isAttrs (t.routedPrefixes or [ ]))
      )
      normalizedTenants;
}
