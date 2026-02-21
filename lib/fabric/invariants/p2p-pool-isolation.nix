{ lib }:

let
  assert_ = cond: msg: if cond then true else throw msg;

  splitCidr =
    cidr:
    let
      parts = lib.splitString "/" (toString cidr);
    in
    {
      ip = builtins.elemAt parts 0;
      prefix = lib.toInt (builtins.elemAt parts 1);
    };

  parseOctet =
    s:
    let
      n = lib.toInt s;
    in
    if n < 0 || n > 255 then throw "bad IPv4 octet" else n;

  parseV4 =
    s:
    let
      p = lib.splitString "." s;
    in
    map parseOctet p;

  v4ToInt =
    o:
    (((builtins.elemAt o 0) * 256 + (builtins.elemAt o 1)) * 256 + (builtins.elemAt o 2)) * 256
    + (builtins.elemAt o 3);

  pow2 = n: if n <= 0 then 1 else 2 * pow2 (n - 1);

  cidrRange4 =
    cidr:
    let
      c = splitCidr cidr;
      base = v4ToInt (parseV4 c.ip);
      size = pow2 (32 - c.prefix);
    in
    {
      start = base;
      end = base + size - 1;
    };

  overlaps = a: b: !(a.end < b.start || b.end < a.start);

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
        if nets == null || !(nets ? ipv4) then [ ] else [ (cidrRange4 nets.ipv4) ]
      ) (builtins.attrNames nodes);

      poolOverlap4 =
        if pool4 == null then
          true
        else
          let
            rPool = cidrRange4 pool4;
          in
          lib.all (
            rUser: assert_ (!(overlaps rPool rUser)) "invariants(p2p-pool): access prefix overlaps p2p pool"
          ) userRanges4;
    in
    builtins.deepSeq poolOverlap4 true;
}
