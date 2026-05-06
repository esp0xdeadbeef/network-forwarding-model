{ lib, ... }:

flatSolvedSites:
let
  overlayWarningsForSite =
    siteKey: site:
    let
      overlayNames = builtins.attrNames (site.overlayReachability or { });
      linkNames = builtins.attrNames (site.links or { });
      hasAccessLaneForOverlay =
        overlayName:
        builtins.any (
          linkName: builtins.match ".*--access-.+--uplink-${overlayName}" linkName != null
        ) linkNames;
      overlayHasTermination =
        overlayName: ((site.overlayReachability.${overlayName}.terminateOn or [ ]) != [ ]);
    in
    lib.concatMap (
      overlayName:
      if overlayHasTermination overlayName && !(hasAccessLaneForOverlay overlayName) then
        [
          "network-forwarding-model: ${siteKey}: overlay '${overlayName}' terminates on core node(s) but has no access-specific uplink lane; Nebula overlay cores must be reached through access/policy traversal, so add an allowed relation from the intended access tenant(s) to external '${overlayName}'"
        ]
      else
        [ ]
    ) overlayNames;
in
lib.concatMap (siteKey: overlayWarningsForSite siteKey flatSolvedSites.${siteKey}) (
  builtins.attrNames flatSolvedSites
)
