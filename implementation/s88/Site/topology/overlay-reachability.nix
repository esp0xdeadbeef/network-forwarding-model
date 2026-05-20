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
  normalizedPrefixRoutes =
    { overlayName
    , peerSiteRef
    , family
    , prefixes
    ,
    }:
    map
      (dst: {
        inherit dst family;
        proto = "overlay";
        overlay = overlayName;
        peerSite = peerSiteRef;
        intent.kind = "overlay-reachability";
      })
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
          tenantPrefixes.prefixesOfSite peerSite;
      terminateOn = lib.unique (overlayTargetNamesFrom overlay);
      explicitPrefixes = explicitPrefixesOf overlay;
      overlayNodePrefixes =
        if peerSite == null then
          {
            ipv4 = [ ];
            ipv6 = [ ];
          }
        else
          overlayNodePrefixesOf peerSite overlayName;
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
          prefixes = lib.unique (peerPrefixes.ipv4 ++ overlayNodePrefixes.ipv4 ++ explicitPrefixes.ipv4);
        };
        routes6 = normalizedPrefixRoutes {
          inherit overlayName peerSiteRef;
          family = 6;
          prefixes = lib.unique (peerPrefixes.ipv6 ++ overlayNodePrefixes.ipv6 ++ explicitPrefixes.ipv6);
        };
      };
    };

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
