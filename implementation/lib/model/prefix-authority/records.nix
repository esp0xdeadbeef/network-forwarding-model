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

  recordFromTenantOwner =
    entry:
    let
      routeIdentity = routeIdentityOf entry;
      family = entry.family;
      authorityClass = authorityClassOf entry;
      id = "prefix-authority::${entry.owner}::${toString family}|${routeIdentity}";
    in
    {
      inherit
        id
        authorityClass
        family
        ;
      owner = entry.owner;
      scopeKind = "node";
      scopeName = entry.owner;
      netName = entry.netName or null;
      reservationState = "assigned";
      childPurpose = common.childPurposeOf authorityClass;
      consumerEligibility = common.eligibilityForClass authorityClass;
      sourceAuthority = {
        kind =
          if entry ? sourceFile then
            "modeled-runtime-routed-prefix"
          else
            "modeled-prefix";
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
    };

  reservationId =
    idx: r:
    toString (r.id or r.name or "reservation-${toString idx}");

  recordFromReservation =
    idx: r:
    let
      authorityClass = r.authorityClass or "reserved-space";
      id = "prefix-reservation::${reservationId idx r}";
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
    // lib.optionalAttrs ((r.sourceFile or null) != null) { sourceFile = toString r.sourceFile; };

in
{
  build =
    { tenantPrefixOwners
    , reservations
    ,
    }:
    (map recordFromTenantOwner (builtins.attrValues tenantPrefixOwners))
    ++ (lib.imap0 recordFromReservation reservations);
}
