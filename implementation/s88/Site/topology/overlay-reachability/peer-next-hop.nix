# Peer overlay next-hop derivation for overlay reachability routes, split out
# of peer-routes.nix so that module stays under the tracked LOC soft limit.
{ lib }:

let
  # The compiled peer site's overlay node addresses, when the peer site is
  # present in this compile pass.
  overlayNodePrefixesOf =
    peerSite: overlayName:
    let
      overlay = (peerSite.overlays or { }).${overlayName} or { };
      nodes = if builtins.isAttrs (overlay.nodes or null) then overlay.nodes else { };
      values = builtins.attrValues nodes;
    in
    {
      ipv4 = builtins.filter (value: builtins.isString value && value != "") (map (node: node.addr4 or null) values);
      ipv6 = builtins.filter (value: builtins.isString value && value != "") (map (node: node.addr6 or null) values);
    };
in
{
  inherit overlayNodePrefixesOf;

  # The peer site's overlay participant next hop for a family.  Preference:
  #   1. the overlay's modeled `peerNodes.<peerSiteRef>.addr4/addr6` (URS: overlay
  #      transport shall model endpoint identity, permitted peers, ...) -- the
  #      peer's overlay address is the same value the peer models as its own
  #      overlay node address, so this is realization, modeled on the overlay
  #      because a peer site is not necessarily compiled in this site's pass;
  #   2. the compiled peer site's overlay node address, when present.
  # Null when neither exists, so the route fails closed rather than being
  # emitted without a next hop.
  nextHopOf =
    overlay: peerSite: peerSiteRef: overlayName: family:
    let
      field = if family == 4 then "addr4" else "addr6";
      modeled =
        let
          raw = (overlay.peerNodes or { }).${toString peerSiteRef} or { };
          v = raw.${field} or null;
        in
        if builtins.isString v && v != "" then v else null;
      compiled =
        if peerSite == null then
          null
        else
          let
            prefixes = overlayNodePrefixesOf peerSite overlayName;
            raw = if family == 4 then prefixes.ipv4 else prefixes.ipv6;
            first = if raw == [ ] then null else builtins.head raw;
          in
          if builtins.isString first then first else null;
      chosen = if modeled != null then modeled else compiled;
      withoutMask = if builtins.isString chosen then builtins.head (lib.splitString "/" chosen) else null;
    in
    if builtins.isString withoutMask && withoutMask != "" then withoutMask else null;
}
