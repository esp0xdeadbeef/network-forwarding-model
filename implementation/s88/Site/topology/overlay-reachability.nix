{ domains
, lib
, overlayItemsFrom
, overlayPeerSiteRefsOf
, overlayTargetNamesFrom
, siteByRef
, tenantPrefixes
,
}:

let
  peerRoutes = import ./overlay-reachability/peer-routes.nix {
    inherit lib tenantPrefixes siteByRef overlayTargetNamesFrom;
  };
  overlayReachabilityForPeer =
    allSites: overlay: peerSiteRef:
    peerRoutes.forPeer { inherit domains allSites; } overlay peerSiteRef;

  overlayReachabilityForOverlay =
    { enterprise
    , allSites
    ,
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
            underlayAccess = null;
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
          underlayAccess =
            if existing.underlayAccess != null then existing.underlayAccess else item.underlayAccess or null;
          routes4 = lib.unique (existing.routes4 ++ item.routes4);
          routes6 = lib.unique (existing.routes6 ++ item.routes6);
        };
    };
in
{
  overlayReachabilityForSite =
    { enterprise
    , site
    , allSites
    ,
    }:
    builtins.foldl' mergeReachability { } (
      map (entry: entry.value) (
        lib.concatMap
          (overlayReachabilityForOverlay { inherit enterprise allSites; })
          (overlayItemsFrom site)
      )
    );
}
