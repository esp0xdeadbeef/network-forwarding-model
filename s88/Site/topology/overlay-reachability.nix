{
  domains,
  lib,
  overlayItemsFrom,
  overlayPeerSiteRefsOf,
  overlayTargetNamesFrom,
  siteByRef,
  tenants,
}:

let
  normalizedPrefixRoutes =
    {
      overlayName,
      peerSiteRef,
      family,
      prefixes,
    }:
    map (dst: {
      inherit dst family;
      proto = "overlay";
      overlay = overlayName;
      peerSite = peerSiteRef;
      intent.kind = "overlay-reachability";
    }) (map toString prefixes);

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

  overlayReachabilityForPeer =
    allSites: overlay: peerSiteRef:
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
          tenants.tenantPrefixesOfSite peerSite;
      terminateOn = lib.unique (overlayTargetNamesFrom overlay);
      explicitPrefixes = explicitPrefixesOf overlay;
    in
    {
      name = overlayName;
      value = {
        overlay = overlayName;
        peerSite = peerSiteRef;
        terminateOn = terminateOn;
        routes4 = normalizedPrefixRoutes {
          inherit overlayName peerSiteRef;
          family = 4;
          prefixes = lib.unique (peerPrefixes.ipv4 ++ explicitPrefixes.ipv4);
        };
        routes6 = normalizedPrefixRoutes {
          inherit overlayName peerSiteRef;
          family = 6;
          prefixes = lib.unique (peerPrefixes.ipv6 ++ explicitPrefixes.ipv6);
        };
      };
    };

  overlayReachabilityForOverlay =
    {
      enterprise,
      allSites,
    }:
    overlay:
    let
      peerRefs = overlayPeerSiteRefsOf enterprise overlay;
    in
    if peerRefs == [ ] then
      [
        (overlayReachabilityForPeer allSites overlay null)
      ]
    else
      map (peerRef: overlayReachabilityForPeer allSites overlay peerRef) peerRefs;

  mergeReachability =
    acc: item:
    let
      existing =
        if builtins.hasAttr item.overlay acc then
          acc.${item.overlay}
        else
          {
            overlay = item.overlay;
            peerSites = [ ];
            terminateOn = [ ];
            routes4 = [ ];
            routes6 = [ ];
          };
      peerSites =
        lib.unique (
          existing.peerSites ++ (if item.peerSite == null then [ ] else [ item.peerSite ])
        );
    in
    acc
    // {
      ${item.overlay} =
        existing
        // {
          peerSite = if peerSites == [ ] then null else builtins.head peerSites;
          peerSites = peerSites;
          terminateOn = lib.unique (existing.terminateOn ++ item.terminateOn);
          routes4 = lib.unique (existing.routes4 ++ item.routes4);
          routes6 = lib.unique (existing.routes6 ++ item.routes6);
        };
    };
in
{
  overlayReachabilityForSite =
    {
      enterprise,
      site,
      allSites,
    }:
    builtins.foldl' mergeReachability { } (
      map (entry: entry.value) (
        lib.concatMap
          (overlayReachabilityForOverlay { inherit enterprise allSites; })
          (overlayItemsFrom site)
      )
    );
}
