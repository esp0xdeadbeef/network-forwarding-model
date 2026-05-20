{ lib, self ? { outPath = ./.; }, ... }:

let
  pairsMod = import (self.outPath + "/implementation/s88/Site/topology/transit/pairs.nix") { inherit lib self; };

in
links: pair:
let
  a = toString (builtins.elemAt pair 0);
  b = toString (builtins.elemAt pair 1);
  members = pairsMod.sortedPair a b;

  _self =
    if a == b then
      throw ''
        network-forwarding-model: transit.ordering must not contain self-links

        node: ${a}
      ''
    else
      true;

  hits = lib.filter
    (
      linkName:
      let
        l = links.${linkName};
        ms = lib.sort (x: y: x < y) (l.members or [ ]);
      in
      (l.kind or null) == "p2p"
      && builtins.length ms == 2
      && (builtins.elemAt ms 0) == members.left
      && (builtins.elemAt ms 1) == members.right
    )
    (builtins.attrNames links);

  _known =
    if hits == [ ] then
      throw ''
        network-forwarding-model: transit.ordering node pair references unknown realized p2p adjacency

        pair: ${a} <-> ${b}
      ''
    else
      true;

  _unique =
    if builtins.length hits == 1 then
      true
    else
      throw ''
        network-forwarding-model: transit.ordering node pair is ambiguous against realized p2p adjacencies

        pair: ${a} <-> ${b}
        links: ${builtins.toJSON hits}
      '';

  linkName = builtins.head hits;
  linkId = links.${linkName}.id or null;

  _id =
    if linkId == null then
      throw ''
        network-forwarding-model: transit link is missing stable identity

        link: ${linkName}
      ''
    else
      true;
in
builtins.seq _self (builtins.seq _known (builtins.seq _unique (builtins.seq _id (toString linkId))))
