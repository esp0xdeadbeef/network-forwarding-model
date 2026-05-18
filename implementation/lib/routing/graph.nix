{ lib, self ? { outPath = ./.; }, ... }:

let
  ip = import (self.outPath + "/lib/net/ip-utils.nix") { inherit lib self; };
  link = import (self.outPath + "/lib/topology/link-utils.nix") { inherit lib self; };
  paths = import ./graph/paths.nix { inherit lib self; };
  trace = import (self.outPath + "/lib/trace.nix") { };

  findLinkBetween =
    {
      links,
      a ? null,
      b ? null,
      from ? null,
      to ? null,
    }:
    let
      left = if a != null then a else from;
      right = if b != null then b else to;
      names = builtins.attrNames links;
      hits = lib.filter (
        lname:
        let
          l = links.${lname};
          m = link.membersOf l;
        in
        lib.elem left m && lib.elem right m
      ) names;
    in
    if hits == [ ] then null else lib.head (lib.sort (x: y: x < y) hits);

  neighborsOf =
    { links, node }:
    let
      names = lib.sort (a: b: a < b) (builtins.attrNames links);
      step =
        acc: lname:
        let
          l = links.${lname};
          m = link.membersOf l;
        in
        if lib.elem node m then acc ++ (lib.filter (x: x != node) m) else acc;
    in
    lib.sort (a: b: a < b) (lib.unique (builtins.foldl' step [ ] names));

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
        builtins.foldl' (
          memberAcc: node:
          builtins.foldl' (
            peerAcc: peer:
            if peer == node then peerAcc else addNeighbor peerAcc node peer
          ) memberAcc members
        ) acc members;
      raw = builtins.foldl' addLink { } (builtins.attrNames links);
    in
    builtins.mapAttrs (_: peers: lib.sort (a: b: a < b) (lib.unique peers)) raw;

  pairKey = a: b: "${toString a}|${toString b}";

  linkPairMap =
    links:
    let
      addPair = acc: a: b: lname:
        let key = pairKey a b;
        in acc // { "${key}" = (acc.${key} or [ ]) ++ [ lname ]; };
      addLink =
        acc: lname:
        let
          members = link.membersOf links.${lname};
        in
        builtins.foldl' (
          memberAcc: a:
          builtins.foldl' (
            peerAcc: b:
            if a == b then peerAcc else addPair peerAcc a b lname
          ) memberAcc members
        ) acc members;
      raw = builtins.foldl' addLink { } (builtins.attrNames links);
    in
    builtins.mapAttrs (_: names: lib.sort (a: b: a < b) (lib.unique names)) raw;

  linksBetween =
    pairs: from: to:
    pairs.${pairKey from to} or [ ];

  shortestPath =
    {
      links,
      src,
      dst,
    }:
    let
      adjacency = neighborMap links;
    in
    shortestPathWithNeighbors {
      neighbors = adjacency;
      inherit src dst;
    };

  shortestPathWithNeighbors = paths.shortestPathWithNeighbors;

  context =
    links:
    let
      neighbors = neighborMap links;
      pairs = linkPairMap links;
    in
    trace.emit "graph:context:links=${toString (builtins.length (builtins.attrNames links))}" {
      inherit neighbors pairs;
      shortestPath = { src, dst }: shortestPathWithNeighbors { inherit neighbors src dst; };
      linksBetween = from: to: linksBetween pairs from to;
      findLinkBetween =
        { a ? null, b ? null, from ? null, to ? null }:
        let
          left = if a != null then a else from;
          right = if b != null then b else to;
          hits = linksBetween pairs left right;
        in
        if hits == [ ] then null else builtins.head hits;
    };

  nextHop =
    {
      links,
      from,
      to,
      stripMask ? ip.stripMask,
    }:
    let
      lname = findLinkBetween { inherit links from to; };
      l = if lname == null then null else links.${lname};
      epTo = if l == null then { } else link.getEp lname l to;
    in
    {
      linkName = lname;
      via4 = if epTo ? addr4 && epTo.addr4 != null then stripMask epTo.addr4 else null;
      via6 = if epTo ? addr6 && epTo.addr6 != null then stripMask epTo.addr6 else null;
    };
in
{
  inherit
    findLinkBetween
    neighborsOf
    shortestPath
    shortestPathWithNeighbors
    neighborMap
    linkPairMap
    linksBetween
    context
    nextHop
    ;
  inherit (link)
    membersOf
    endpointsOf
    chooseEndpointKey
    getEp
    ;
}
