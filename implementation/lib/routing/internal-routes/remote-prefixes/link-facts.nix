{ lib, self ? { outPath = ./.; }, ... }:

let
  link = import (self.outPath + "/implementation/lib/topology/link-utils.nix") { inherit lib self; };
  laneMetadata = import (self.outPath + "/implementation/lib/routing/lane-metadata.nix") {
    inherit lib self;
  };
  inherit (laneMetadata)
    laneAccessNodeName
    laneUplinkName
    ;

  addUnique = acc: name: value:
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
          members = link.membersOf linkObj;
          accWithNodeUplinks =
            if accessNodeName != null || uplinkName == null then
              acc
            else
              builtins.foldl'
                (
                  nodeAcc: member:
                  nodeAcc // { uplinksByNode = addUnique nodeAcc.uplinksByNode member uplinkName; }
                )
                acc
                members;
        in
        if accessNodeName == null || uplinkName == null then
          accWithNodeUplinks
        else
          accWithNodeUplinks // {
            uplinksByAccess = addUnique accWithNodeUplinks.uplinksByAccess accessNodeName uplinkName;
          }
      )
      { uplinksByNode = { }; uplinksByAccess = { }; }
      (builtins.attrNames links);
}
