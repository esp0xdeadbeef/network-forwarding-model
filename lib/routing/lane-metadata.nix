{ lib }:

let
  overlayUplinkNameSet =
    topo:
    lib.listToAttrs (
      map (name: {
        inherit name;
        value = true;
      }) (builtins.attrNames (topo.overlayReachability or { }))
    );
in
rec {
  hasUplinkLaneSuffix = linkName: builtins.match ".*--uplink-.+" (toString linkName) != null;

  laneUplinkNameFromLinkName =
    linkName:
    let
      parts = lib.splitString "--uplink-" (toString linkName);
    in
    if builtins.length parts < 2 then null else builtins.elemAt parts ((builtins.length parts) - 1);

  laneAccessNodeNameFromLinkName =
    linkName:
    let
      parts = lib.splitString "--access-" (toString linkName);
      lastPart =
        if builtins.length parts < 2 then null else builtins.elemAt parts ((builtins.length parts) - 1);
      segments = if lastPart == null then [ ] else lib.splitString "--uplink-" lastPart;
    in
    if segments == [ ] then null else builtins.elemAt segments 0;

  defaultMetricForLane =
    topo: linkName:
    let
      uplinkName = laneUplinkNameFromLinkName linkName;
      overlayNames = overlayUplinkNameSet topo;
    in
    if uplinkName == null then null else if builtins.hasAttr uplinkName overlayNames then 2000 else 1000;
}
