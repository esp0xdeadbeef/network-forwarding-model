{ lib }:

let
  overlayPeerSiteRefOf =
    enterprise: overlay:
    let
      raw =
        overlay.peerSite or overlay.peerSiteId or overlay.remoteSite or overlay.site or overlay.peer
          or null;
      s =
        if raw == null then
          null
        else if builtins.isString raw then
          toString raw
        else if builtins.isAttrs raw && (raw.site or null) != null then
          toString raw.site
        else if builtins.isAttrs raw && (raw.siteId or null) != null then
          toString raw.siteId
        else if builtins.isAttrs raw && (raw.name or null) != null then
          toString raw.name
        else
          null;
    in
    if s == null then
      null
    else if lib.hasInfix "." s then
      s
    else
      "${enterprise}.${s}";

  overlayPeerSiteRefsOf =
    enterprise: overlay:
    let
      rawPeers =
        if builtins.isList (overlay.peerSites or null) then
          overlay.peerSites
        else if builtins.isList (overlay.peers or null) then
          overlay.peers
        else
          [ ];
      explicitPeers = lib.filter (value: value != null) rawPeers;
      singlePeer = overlayPeerSiteRefOf enterprise overlay;
      peerRefs =
        if explicitPeers != [ ] then
          map (
            peer:
            overlayPeerSiteRefOf enterprise (
              overlay
              // {
                peerSite = peer;
                peerSites = null;
                peers = null;
              }
            )
          ) explicitPeers
        else if singlePeer != null then
          [ singlePeer ]
        else
          [ ];
    in
    lib.unique (lib.filter (value: value != null) peerRefs);
in
{
  inherit overlayPeerSiteRefOf overlayPeerSiteRefsOf;
}
