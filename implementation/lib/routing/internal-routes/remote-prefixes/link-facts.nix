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
    laneScopeName
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
          scopeName = laneScopeName linkObj;
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
            inner: uplink:
            inner
            // { uplinksByAccess = addUnique inner.uplinksByAccess accessNodeName uplink; }
            // lib.optionalAttrs (scopeName != null) {
              uplinksByScope = addUnique inner.uplinksByScope scopeName uplink;
            }
            # FS-171/FS-370: a route entry's owner may be the source scope (a
            # tenant) or the access unit that serves it. Index the lane's
            # uplinks under both so the internal-route reachability check
            # resolves regardless of which identity the owner carries.
            // lib.optionalAttrs (accessNodeName != null) {
              uplinksByScope = addUnique inner.uplinksByScope accessNodeName uplink;
            }
          ) accWithNodeUplinks uplinkNames
      )
      {
        uplinksByNode = { };
        uplinksByAccess = { };
        uplinksByScope = { };
      }
      (builtins.attrNames links);
}
