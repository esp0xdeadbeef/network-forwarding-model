{
  lib,
  self ? {
    outPath = ./.;
  },
  ...
}:

let
  link = import (self.outPath + "/implementation/lib/topology/link-utils.nix") { inherit lib self; };
  laneMetadata = import ./lane-metadata.nix { inherit lib self; };
  inherit (laneMetadata)
    laneAccessNodeName
    laneUplinkName
    ;

  uplinkHasDefault =
    routeFacts: uplinkName: builtins.hasAttr uplinkName (routeFacts.uplinkHasDefaultSet or { });

  uplinkHasExecutableDefault =
    routeFacts: uplinkName:
    uplinkHasDefault routeFacts uplinkName
    || builtins.hasAttr uplinkName (routeFacts.overlayUplinkNameSet or { });

  # Finds the selector-to-core transport link that carries the given uplink
  # name. The core end is the non-selector member of that link.
  coreLinkForUplink =
    topo: selectorNodeName: uplinkName:
    let
      links = topo.links or { };
      linkNames = lib.sort (a: b: a < b) (builtins.attrNames links);
      matches = lib.filter (
        linkName:
        let
          linkObj = links.${linkName};
          members = link.membersOf linkObj;
        in
        lib.elem selectorNodeName members
        && laneAccessNodeName linkObj == null
        && laneUplinkName linkObj == uplinkName
        && lib.any (memberName: ((topo.nodes or { }).${memberName} or { }).role or null == "core") members
      ) linkNames;
    in
    if matches == [ ] then null else builtins.head matches;

  coreEpForUplink =
    topo: selectorNodeName: uplinkName:
    let
      links = topo.links or { };
      coreLinkName = coreLinkForUplink topo selectorNodeName uplinkName;
    in
    if coreLinkName == null then
      null
    else
      link.getEp coreLinkName links.${coreLinkName} (
        builtins.head (
          lib.filter (memberName: memberName != selectorNodeName) (link.membersOf links.${coreLinkName})
        )
      );
in
{
  inherit
    uplinkHasDefault
    uplinkHasExecutableDefault
    coreLinkForUplink
    coreEpForUplink
    ;
}
