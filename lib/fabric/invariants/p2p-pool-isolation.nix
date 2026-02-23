# ./lib/fabric/invariants/p2p-pool-isolation.nix
{ lib }:

let
  cidr = import ./cidr-utils.nix { inherit lib; };

  assert_ = cond: msg: if cond then true else throw msg;

  overlaps = a: b: a.family == b.family && !(a.end < b.start || b.end < a.start);

in
{
  check =
    { site, ... }:
    let
      nodes = site.nodes or { };
      p2pPool = site.p2p-pool or { };
      pool4 = p2pPool.ipv4 or null;

      userRanges4 = lib.concatMap (
        name:
        let
          n = nodes.${name};
          nets = n.networks or null;
        in
        if nets == null || !(nets ? ipv4) then
          [ ]
        else
          [ (cidr.cidrRange nets.ipv4) ]
      ) (builtins.attrNames nodes);

      poolOverlap4 =
        if pool4 == null then
          true
        else
          let
            rPool = cidr.cidrRange pool4;
          in
          lib.all (
            rUser:
            assert_ (!(overlaps rPool rUser)) "invariants(p2p-pool): access prefix overlaps p2p pool"
          ) userRanges4;
    in
    builtins.deepSeq poolOverlap4 true;
}
