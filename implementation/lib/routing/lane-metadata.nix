{ lib, self ? { outPath = ./.; }, ... }:

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
  laneMeta =
    link:
    if builtins.isAttrs (link.laneMeta or null) then link.laneMeta else { };

  hasUplinkLane = link: (laneMeta link).uplink or null != null;

  laneUplinkName = link: (laneMeta link).uplink or null;

  laneAccessNodeName = link: (laneMeta link).access or null;

  defaultMetricForLane =
    topo: link:
    let
      uplinkName = laneUplinkName link;
      overlayNames = overlayUplinkNameSet topo;
    in
    if uplinkName == null then null else if builtins.hasAttr uplinkName overlayNames then 2000 else 1000;
}
