# Runtime-routed overlay peer routes, split out of peer-routes.nix so that
# module stays under the tracked LOC soft limit.
#
# A delegated/runtime allocation has no modeled prefix value: its concrete
# destination is only known at runtime from the referenced source file. Such a
# peer prefix therefore cannot appear in the prefix route set, where every route
# carries a modeled destination. It is emitted here as a destination-less
# record that keeps the runtime source reference and its delegated metadata,
# which is what downstream layers consume to materialize dynamic (source-file
# driven) authority instead of hardcoding a CIDR.
#
# FS-460 requires the delegated path to carry its address authority and
# return-route expectation; FS-171 makes this layer the single writer of the
# overlay peer route set.
#
# FS-350-SMS-030: a host-only provider prefix (`perTenantPrefixLength` equal to
# the host length, authority class `host-only-provider-prefix`) is an overlay
# participant address, not delegated tenant-prefix authority, so it must not be
# carried in the overlay participant ledger (nor in the overlay reachability
# route set). The authority class is taken from the site's normalized tenant
# prefix entries; this module never re-derives it.
{ lib }:

let
  hostOnlyAuthorityClass = "host-only-provider-prefix";

  routeOf =
    { overlayName
    , peerSiteRef
    , family
    , via
    ,
    }:
    entry:
    {
      proto = "overlay";
      inherit family;
      inherit (entry) sourceFile;
      overlay = overlayName;
      peerSite = peerSiteRef;
      intent.kind = "overlay-reachability";
    }
    // lib.optionalAttrs (entry.tenantName != null) { tenant = entry.tenantName; }
    // builtins.removeAttrs entry [
      "family"
      "sourceFile"
      "tenantName"
      "authorityClass"
    ]
    // lib.optionalAttrs (via != null) { ${if family == 4 then "via4" else "via6"} = via; };
in
{
  # Destination-less runtime return records for one overlay peer and family.
  routesFor =
    { entries
    , overlayName
    , peerSiteRef
    , family
    , via
    ,
    }:
    let
      selected = lib.filter
        (
          entry: entry.family == family && entry.authorityClass != hostOnlyAuthorityClass
        )
        entries;
    in
    # Every overlay reachability route carries the peer-site overlay next hop
      # (FS-460 / SDS-HDS-SMS-030): a `proto = overlay` route without a via is not
      # installable. Fail closed here, at the owning layer, instead of emitting a
      # via-less record downstream.
    if selected == [ ] then
      [ ]
    else if via == null then
      throw "overlay-peer-next-hop-unbound: overlay '${overlayName}' peer '${
        if peerSiteRef == null then "<none>" else toString peerSiteRef
      }' has runtime routed prefixes but no peer overlay node address for family ${toString family} to use as their next hop; model the peer's overlay node address (URS: overlay transport models endpoint identity)"
    else
      map (routeOf { inherit overlayName peerSiteRef family via; }) selected;
}
