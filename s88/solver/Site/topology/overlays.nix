{ lib }:

let
  domains = import ./domains.nix { inherit lib; };
  peerSites = import ./overlay-peer-sites.nix { inherit lib; };
  tenants = import ./tenants.nix { inherit lib; };

  normalizeOverlay =
    x:
    if builtins.isString x then
      {
        name = toString x;
      }
    else if builtins.isAttrs x && (x.name or null) != null then
      x // { name = toString x.name; }
    else
      null;

  overlayItemsFrom =
    site:
    let
      overlays0 = ((site.transport or { }).overlays or [ ]);
    in
    if builtins.isList overlays0 then
      lib.filter (x: x != null) (map normalizeOverlay overlays0)
    else if builtins.isAttrs overlays0 then
      lib.filter (x: x != null) (
        lib.mapAttrsToList (name: v: normalizeOverlay (v // { inherit name; })) overlays0
      )
    else
      [ ];

  overlayTargetNamesFrom =
    x:
    if x == null then
      [ ]
    else if builtins.isString x then
      [ (toString x) ]
    else if builtins.isList x then
      lib.concatMap overlayTargetNamesFrom x
    else if builtins.isAttrs x then
      let
        direct = lib.filter (v: v != null) [
          (if (x.unit or null) != null then toString x.unit else null)
          (if (x.node or null) != null then toString x.node else null)
        ];
      in
      if direct != [ ] then
        direct
      else
        lib.concatMap overlayTargetNamesFrom (
          lib.filter (v: v != null) [
            (x.terminateOn or null)
            (x.terminatesOn or null)
            (x.terminatedOn or null)
          ]
        )
    else
      [ ];

  siteByRef =
    allSites: ref:
    let
      parts = lib.splitString "." (toString ref);
    in
    if builtins.length parts != 2 then
      null
    else
      let
        ent = builtins.elemAt parts 0;
        sid = builtins.elemAt parts 1;
      in
      if allSites ? "${ent}" && builtins.isAttrs allSites.${ent} && allSites.${ent} ? "${sid}" then
        allSites.${ent}.${sid}
      else
        null;

  reachability = import ./overlay-reachability.nix {
    inherit
      domains
      lib
      overlayItemsFrom
      overlayTargetNamesFrom
      siteByRef
      tenants
      ;
    inherit (peerSites) overlayPeerSiteRefsOf;
  };

in
{
  inherit
    normalizeOverlay
    overlayItemsFrom
    overlayTargetNamesFrom
    siteByRef
    ;
  inherit (peerSites) overlayPeerSiteRefOf overlayPeerSiteRefsOf;
  inherit (reachability) overlayReachabilityForSite;
}
