{
  lib,
  self ? {
    outPath = ./.;
  },
  ...
}:

let
  link = import (self.outPath + "/implementation/lib/topology/link-utils.nix") { inherit lib self; };
  laneMetadata = import (self.outPath + "/implementation/lib/routing/lane-metadata.nix") {
    inherit lib self;
  };
  inherit (laneMetadata)
    laneAccessNodeName
    laneMeta
    laneUplinkName
    ;

  addUnique =
    acc: name: value:
    acc // { "${name}" = lib.unique ((acc.${name} or [ ]) ++ [ value ]); };

in
{
  build =
    { links }:
    builtins.foldl'
      (
        acc: linkName:
        let
          linkObj = links.${linkName};
          uplinkName = laneUplinkName linkObj;
          accessNodeName = laneAccessNodeName linkObj;
          uplinkNames = if uplinkName != null then [ uplinkName ] else (laneMeta linkObj).uplinks or [ ];
          members = link.membersOf linkObj;
          accWithNodeUplinks =
            if accessNodeName != null || uplinkNames == [ ] then
              acc
            else
              builtins.foldl' (
                nodeAcc: member:
                builtins.foldl' (
                  inner: uplink: inner // { uplinksByNode = addUnique inner.uplinksByNode member uplink; }
                ) nodeAcc uplinkNames
              ) acc members;
        in
        if accessNodeName == null || uplinkNames == [ ] then
          accWithNodeUplinks
        else
          builtins.foldl' (
            inner: uplink: inner // { uplinksByAccess = addUnique inner.uplinksByAccess accessNodeName uplink; }
          ) accWithNodeUplinks uplinkNames
      )
      {
        uplinksByNode = { };
        uplinksByAccess = { };
      }
      (builtins.attrNames links);
}
