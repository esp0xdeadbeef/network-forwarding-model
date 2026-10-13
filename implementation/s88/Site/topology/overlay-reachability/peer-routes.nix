# Overlay peer route derivation, split out of overlay-reachability.nix so that
# module stays under the tracked LOC soft limit.
{ lib, tenantPrefixes, siteByRef, overlayTargetNamesFrom }:

let
  normalizedPrefixRoutes =
    { overlayName
    , peerSiteRef
    , family
    , prefixes
    , via
    ,
    }:
    let
      viaField = if family == 4 then "via4" else "via6";
      peerLabel = if peerSiteRef == null then "<none>" else toString peerSiteRef;
    in
    # Every overlay reachability route must carry the peer-site overlay next hop
    # (FS-460 / SDS-HDS-SMS-030): a `proto = overlay` route is only installable
    # with a via, and an inner-communication overlay always has a peer endpoint.
    # Fail closed at this owning layer (the forwarding model is the authoritative
    # writer of the overlay peer route set) instead of emitting a via-less route.
    if via == null && prefixes != [ ] then
      throw "overlay-peer-next-hop-unbound: overlay '${overlayName}' peer '${peerLabel}' has reachable prefixes but no peer overlay node address for family ${toString family} to use as its next hop; model the peer's overlay node address (URS: overlay transport models endpoint identity)"
    else
      map
        (dst: {
          inherit dst family;
          proto = "overlay";
          overlay = overlayName;
          peerSite = peerSiteRef;
          intent.kind = "overlay-reachability";
        }
        // { ${viaField} = via; })
        (map toString prefixes);

  explicitPrefixesOf =
    overlay:
    let
      prefixes = overlay.prefixes or { };
      ipv4 = if builtins.isList (prefixes.ipv4 or null) then prefixes.ipv4 else [ ];
      ipv6 = if builtins.isList (prefixes.ipv6 or null) then prefixes.ipv6 else [ ];
    in
    {
      inherit ipv4 ipv6;
    };

  overlayUnderlayAccessOf =
    overlay:
    let
      underlayAccess = overlay.underlayAccess or null;
    in
    if builtins.isAttrs underlayAccess then underlayAccess else null;

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

  # The peer site's overlay participant next hop for a family.  Preference:
  #   1. the overlay's modeled `peerNodes.<peerSiteRef>.addr4/addr6` (URS: overlay
  #      transport models endpoint identity) -- available even when the peer site
  #      is not compiled in this site's pass;
  #   2. the compiled peer site's overlay node address, when present.
  # Null when neither exists, so the route fails closed rather than being
  # emitted without a next hop.
  overlayPeerNextHopOf =
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

  # URS (Reachability, Routing, and Overlays): "Overlay transport shall model
  # endpoint identity, permitted peers, bootstrap dependencies, imported and
  # exported prefixes, payload classes, MTU constraints, secret lifecycle,
  # readiness, and fail-closed or failover behavior."
  #
  # A peer overlay's route set toward the peer is the overlay's MODELED
  # imported prefixes (what this site routes through the overlay), for both
  # address families. The peer's tenant subnets are only a fallback when the
  # peer site is present in the compile.
  modeledImportedPrefixes =
    overlay: family:
    let
      prefixes = overlay.prefixes or null;
      imported = if builtins.isAttrs prefixes then prefixes.imported or null else null;
      value = if builtins.isAttrs imported then imported.${family} or [ ] else [ ];
    in
    if builtins.isList value then map toString value else [ ];

  overlayDeclaresModeledPrefixes = overlay: builtins.isAttrs (overlay.prefixes or null);
in
{
  # Resolve one peer-entry of an overlay into the aggregated reachability record.
  forPeer =
    {
      domains,
      allSites,
    }:
    overlay: peerSiteRef:
    let
      overlayName = toString overlay.name;
      peerSite0 = if peerSiteRef == null then null else siteByRef allSites peerSiteRef;
      peerSite =
        if peerSite0 == null then
          null
        else
          peerSite0 // { domains = domains.materializeSiteDomains peerSite0; };
      peerPrefixes =
        if peerSite == null then
          {
            ipv4 = [ ];
            ipv6 = [ ];
          }
        else
          tenantPrefixes.prefixesOfSite peerSite;
      terminateOn = lib.unique (overlayTargetNamesFrom overlay);
      explicitPrefixes = explicitPrefixesOf overlay;
      explicitPrefixValues = explicitPrefixes.ipv4 ++ explicitPrefixes.ipv6;
      peerLabel = if peerSiteRef == null then "<none>" else toString peerSiteRef;
      importedIpv4 = modeledImportedPrefixes overlay "ipv4";
      importedIpv6 = modeledImportedPrefixes overlay "ipv6";
      hasModeledPrefixes = overlayDeclaresModeledPrefixes overlay;
      # Fail closed (URS: "A routing feature that cannot be satisfied by the
      # modeled selection fails loudly at the owning layer instead of being
      # silently omitted or approximated."): a peer overlay that reaches a peer
      # the compile does not contain and models no imported prefixes would
      # otherwise emit an empty route set that looks like a working feature.
      _peerReachabilitySatisfiable =
        peerSite != null
        || peerSiteRef == null
        || hasModeledPrefixes
        || throw "overlay-peer-prefixes-unbound: overlay '${overlayName}' peer '${peerLabel}' is not present in this compile and the overlay declares no modeled imported prefixes; model the overlay's imported/exported prefixes (URS: overlay transport models imported and exported prefixes) so the peer route set is explicit";
      explicitPrefixesAreBound =
        if explicitPrefixValues == [ ] then
          true
        else
          throw "overlay-source-prefix-unbound: overlay '${overlayName}' peer '${peerLabel}' declares explicit prefixes ${builtins.toJSON explicitPrefixValues}; model those prefixes as peer tenant ownership or overlay node addresses before exporting overlay reachability";
      underlayAccess = overlayUnderlayAccessOf overlay;
      overlayNodePrefixes =
        if peerSite == null then
          {
            ipv4 = [ ];
            ipv6 = [ ];
          }
        else
          overlayNodePrefixesOf peerSite overlayName;
      # Modeled imported prefixes are the authoritative peer route set; the
      # peer-site derivation remains for the both-sites-compiled case.
      routePrefixesFor =
        family: peerFamily: imported:
        if hasModeledPrefixes then
          lib.unique (imported ++ explicitPrefixes.${family})
        else
          lib.unique (peerFamily ++ overlayNodePrefixes.${family} ++ explicitPrefixes.${family});
    in
    {
      name = overlayName;
      value = builtins.seq _peerReachabilitySatisfiable (builtins.seq explicitPrefixesAreBound {
        overlay = overlayName;
        peerSite = peerSiteRef;
        terminateOn = terminateOn;
        inherit underlayAccess;
        routes4 = normalizedPrefixRoutes {
          inherit overlayName peerSiteRef;
          family = 4;
          prefixes = routePrefixesFor "ipv4" peerPrefixes.ipv4 importedIpv4;
          via = overlayPeerNextHopOf overlay peerSite peerSiteRef overlayName 4;
        };
        routes6 = normalizedPrefixRoutes {
          inherit overlayName peerSiteRef;
          family = 6;
          prefixes = routePrefixesFor "ipv6" peerPrefixes.ipv6 importedIpv6;
          via = overlayPeerNextHopOf overlay peerSite peerSiteRef overlayName 6;
        };
      });
    };
}
