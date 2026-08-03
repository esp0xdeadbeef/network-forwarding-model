{ lib, self ? { outPath = ./.; }, ... }:

let
  common = import ./common.nix { inherit lib self; };

  routeIdentityOf =
    e:
    if e ? dst then
      e.dst
    else if e ? sourceFile then
      "source:${e.sourceFile}"
    else
      null;

  # Determine if an IPv4 prefix string represents a private/reserved range.
  isPrivateIPv4 = prefix:
    let
      ip = lib.head (lib.splitString "/" (toString prefix));
      octets = map lib.toInt (lib.splitString "." ip);
      o1 = builtins.elemAt octets 0;
      o2 = builtins.elemAt octets 1;
    in
    o1 == 10 || (o1 == 172 && o2 >= 16 && o2 <= 31) || (o1 == 192 && o2 == 168)
    || (o1 == 100 && o2 >= 64 && o2 <= 127) || o1 == 127;

  # Determine if an IPv6 prefix string represents ULA (fc00::/7).
  isULA = prefix:
    let
      ip = lib.head (lib.splitString "/" (toString prefix));
      lower = lib.toLower ip;
    in
    lib.hasPrefix "fc" lower || lib.hasPrefix "fd" lower;

  # Classify an authority class as public, protected, or other.
  authorityClassCategory = cls:
    if builtins.elem cls [ "routed-public-ipv4" "routed-client-prefix"
      "delegated-client-prefix" "tunneled-client-prefix" "provider-owned-client-prefix" ] then
      "public"
    else if builtins.elem cls [ "access-subnet-pool" "host-only-provider-prefix" ] then
      "protected"
    else
      "other";

  authorityClassOf =
    e:
    if (e.authorityClass or null) != null then
      toString e.authorityClass
    else if (e.kind or null) == "runtime-routed-prefix" then
      "routed-client-prefix"
    else if (e.kind or null) == "routed-public-ipv4" then
      "routed-public-ipv4"
    else
      "access-subnet-pool";

  # Detect authority class mixing for entries: explicit authorityClass contradicts kind.
  entryMixingDiag = e: authorityClass:
    let
      kind = e.kind or null;
      isPublicKind = kind != null
        && builtins.elem kind [ "routed-public-ipv4" "runtime-routed-prefix" ];
      cat = authorityClassCategory authorityClass;
    in
    if isPublicKind && cat == "protected" then
      { code = "authority-class-mixing";
        message = "entry with kind '${toString kind}' (public) has protected authority class '${authorityClass}'";
        affectedAuthorityClass = authorityClass; conflictingClasses = [ "public" "protected" ];
        entryKind = toString kind; }
    else if kind == null && !isPublicKind && cat == "public" then
      { code = "authority-class-mixing";
        message = "entry (derived protected kind) has public authority class '${authorityClass}'";
        affectedAuthorityClass = authorityClass; conflictingClasses = [ "protected" "public" ];
        entryKind = null; }
    else null;

  # Detect authority class mixing for reservations: prefix public/private vs authorityClass.
  reservationMixingDiag = r: authorityClass:
    let
      cat = authorityClassCategory authorityClass;
      prefix = r.prefix or null;
      family = r.family or null;
      isPublic =
        if prefix == null then null
        else if family == 4 || (family == null && !(lib.hasInfix ":" (toString prefix))) then
          !(isPrivateIPv4 prefix)
        else !(isULA prefix);
    in
    if isPublic == null then null
    else if isPublic && cat == "protected" then
      { code = "authority-class-mixing";
        message = "reservation prefix '${toString prefix}' is public but authority class '${authorityClass}' is protected";
        affectedAuthorityClass = authorityClass; conflictingClasses = [ "public" "protected" ];
        prefix = toString prefix; }
    else if !isPublic && cat == "public" then
      { code = "authority-class-mixing";
        message = "reservation prefix '${toString prefix}' is private but authority class '${authorityClass}' is public";
        affectedAuthorityClass = authorityClass; conflictingClasses = [ "protected" "public" ];
        prefix = toString prefix; }
    else null;

  recordFromTenantOwner =
    entry:
    let
      routeIdentity = routeIdentityOf entry;
      family = entry.family;
      authorityClass = authorityClassOf entry;
      id = "prefix-authority::${entry.owner}::${toString family}|${routeIdentity}";
      mixingDiag = entryMixingDiag entry authorityClass;
    in
    {
      inherit id authorityClass family;
      owner = entry.owner;
      scopeKind = "node";
      scopeName = entry.owner;
      netName = entry.netName or null;
      reservationState = "assigned";
      childPurpose = common.childPurposeOf authorityClass;
      consumerEligibility = common.eligibilityForClass authorityClass;
      sourceAuthority = {
        kind =
          if entry ? sourceFile then "modeled-runtime-routed-prefix"
          else "modeled-prefix";
        owner = entry.owner;
        routeIdentity = routeIdentity;
      }
      // lib.optionalAttrs (entry ? dst) { prefix = entry.dst; }
      // lib.optionalAttrs ((entry.source or null) != null) { source = entry.source; }
      // lib.optionalAttrs (entry ? sourceFile) {
        sourceFile = entry.sourceFile;
        prefixName = entry.prefixName or null;
        delegatedPrefixLength = entry.delegatedPrefixLength or null;
        perTenantPrefixLength = entry.perTenantPrefixLength or null;
        slot = entry.slot or null;
      };
    }
    // lib.optionalAttrs (entry ? dst) { prefix = entry.dst; }
    // lib.optionalAttrs ((entry.source or null) != null) { source = entry.source; }
    // lib.optionalAttrs (entry ? sourceFile) {
      sourceFile = entry.sourceFile;
      prefixName = entry.prefixName or null;
      delegatedPrefixLength = entry.delegatedPrefixLength or null;
      perTenantPrefixLength = entry.perTenantPrefixLength or null;
      slot = entry.slot or null;
    }
    // lib.optionalAttrs (mixingDiag != null) { diagnostics = [ mixingDiag ]; };

  reservationId = idx: r:
    toString (r.id or r.name or "reservation-${toString idx}");

  recordFromReservation =
    idx: r:
    let
      authorityClass = r.authorityClass or "reserved-space";
      id = "prefix-reservation::${reservationId idx r}";
      mixingDiag = reservationMixingDiag r authorityClass;
    in
    {
      inherit id authorityClass;
      family = r.family or null;
      owner = r.owner or null;
      scopeKind = r.scopeKind or "site";
      scopeName = r.scopeName or null;
      reservationState = r.reservationState or r.state or "reserved";
      childPurpose = common.childPurposeOf authorityClass;
      consumerEligibility = common.denyAll;
      sourceAuthority = {
        kind = "modeled-reservation";
        name = reservationId idx r;
      }
      // lib.optionalAttrs ((r.prefix or null) != null) { prefix = toString r.prefix; }
      // lib.optionalAttrs ((r.sourceFile or null) != null) { sourceFile = toString r.sourceFile; };
    }
    // lib.optionalAttrs ((r.prefix or null) != null) { prefix = toString r.prefix; }
    // lib.optionalAttrs ((r.sourceFile or null) != null) { sourceFile = toString r.sourceFile; }
    // lib.optionalAttrs (mixingDiag != null) { diagnostics = [ mixingDiag ]; };

in
{
  build =
    { tenantPrefixOwners, reservations }:
    (map recordFromTenantOwner (builtins.attrValues tenantPrefixOwners))
    ++ (lib.imap0 recordFromReservation reservations);
}
