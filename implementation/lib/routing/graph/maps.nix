{ lib, self ? { outPath = ./.; }, ... }:

let
  link = import (self.outPath + "/implementation/lib/topology/link-utils.nix") { inherit lib self; };
  pairKey = a: b: "${toString a}|${toString b}";
in
{
  inherit pairKey;

  neighborMap =
    links:
    let
      addNeighbor = acc: node: peer:
        acc // { "${node}" = (acc.${node} or [ ]) ++ [ peer ]; };
      addLink =
        acc: lname:
        let
          members = link.membersOf links.${lname};
        in
        builtins.foldl'
          (
            memberAcc: node:
            builtins.foldl'
              (
                peerAcc: peer:
                if peer == node then peerAcc else addNeighbor peerAcc node peer
              )
              memberAcc
              members
          )
          acc
          members;
      raw = builtins.foldl' addLink { } (builtins.attrNames links);
    in
    builtins.mapAttrs (_: peers: lib.sort (a: b: a < b) (lib.unique peers)) raw;

  linkPairMap =
    links:
    let
      addPair = acc: a: b: lname:
        let
          key = pairKey a b;
        in
        acc // { "${key}" = (acc.${key} or [ ]) ++ [ lname ]; };
      addLink =
        acc: lname:
        let
          members = link.membersOf links.${lname};
        in
        builtins.foldl'
          (
            memberAcc: a:
            builtins.foldl'
              (
                peerAcc: b:
                if a == b then peerAcc else addPair peerAcc a b lname
              )
              memberAcc
              members
          )
          acc
          members;
      raw = builtins.foldl' addLink { } (builtins.attrNames links);
    in
    builtins.mapAttrs (_: names: lib.sort (a: b: a < b) (lib.unique names)) raw;

  linksBetween = pairs: from: to: pairs.${pairKey from to} or [ ];
}
