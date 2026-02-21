{ lib }:

let
  addr = import ../model/addressing.nix { inherit lib; };

  splitCidr =
    cidr:
    let
      parts = lib.splitString "/" cidr;
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
    if n < 0 || n > 255 then throw "p2p pool exhausted" else n;

  parseV4 =
    s:
    let
      p = lib.splitString "." s;
    in
    if builtins.length p != 4 then throw "p2p.alloc: bad IPv4 '${s}'" else map parseOctet p;

  v4ToInt =
    o:
    (((builtins.elemAt o 0) * 256 + (builtins.elemAt o 1)) * 256 + (builtins.elemAt o 2)) * 256
    + (builtins.elemAt o 3);

  intToV4 =
    n:
    let
      o0 = builtins.div n (256 * 256 * 256);
      r0 = n - o0 * (256 * 256 * 256);
      o1 = builtins.div r0 (256 * 256);
      r1 = r0 - o1 * (256 * 256);
      o2 = builtins.div r1 256;
      o3 = r1 - o2 * 256;
    in
    lib.concatStringsSep "." (
      map toString [
        o0
        o1
        o2
        o3
      ]
    );

  pow2 = n: if n <= 0 then 1 else 2 * pow2 (n - 1);

  rangeV4 =
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

  normPair =
    pair:
    let
      a0 = builtins.elemAt pair 0;
      b0 = builtins.elemAt pair 1;
    in
    if a0 < b0 then
      {
        a = a0;
        b = b0;
      }
    else
      {
        a = b0;
        b = a0;
      };

  pairKey = p: "${p.a}|${p.b}";

  splitIPv6 =
    cidr:
    let
      parts = lib.splitString "/" cidr;
    in
    {
      ip = builtins.elemAt parts 0;
      prefix = lib.toInt (builtins.elemAt parts 1);
    };

  allocIPv6Pair =
    { pool, linkIndex }:
    let
      c = splitIPv6 pool;

      hostBase = linkIndex * 2;

      a = addr.hostCidr hostBase "${c.ip}/127";
      b = addr.hostCidr (hostBase + 1) "${c.ip}/127";
    in
    {
      inherit a b;
    };

in
{
  alloc =
    { site }:
    let
      p2p = site.p2p-pool;
      links = site.links;

      v4 = splitCidr p2p.ipv4;
      base4 = v4ToInt (parseV4 v4.ip);

      pool6 = p2p.ipv6 or null;

      userRanges =
        let
          nodes = site.nodes or { };
        in
        lib.concatMap (
          name:
          let
            n = nodes.${name};
            nets = n.networks or null;
          in
          if nets == null || !(nets ? ipv4) then [ ] else [ (rangeV4 nets.ipv4) ]
        ) (builtins.attrNames nodes);

      ps0 = map normPair links;
      ps = lib.sort (x: y: pairKey x < pairKey y) ps0;

      totalHosts = pow2 (32 - v4.prefix);
      maxBlocks = builtins.div totalHosts 2;

      allocOne =
        used: idx:
        if idx >= maxBlocks then
          throw "p2p pool exhausted"
        else
          let
            offA = 2 * idx;
            offB = offA + 1;

            r = {
              start = base4 + offA;
              end = base4 + offB;
            };

            collides = lib.any (u: overlaps u r) (used ++ userRanges);
          in
          if collides then
            allocOne used (idx + 1)
          else
            {
              range = r;
              nextIdx = idx + 1;
            };

      step =
        acc: p:
        let
          found = allocOne acc.used acc.idx;

          hostA = found.range.start;
          hostB = found.range.start + 1;

          addr4A = "${intToV4 hostA}/31";
          addr4B = "${intToV4 hostB}/31";

          linkIndex =
            let
              off = found.range.start - base4;
            in
            builtins.div off 2;

          v6pair =
            if pool6 == null then
              {
                a = null;
                b = null;
              }
            else
              allocIPv6Pair {
                pool = pool6;
                inherit linkIndex;
              };

          linkName = "p2p-${p.a}-${p.b}";
        in
        {
          idx = found.nextIdx;
          used = acc.used ++ [ found.range ];
          attrs = acc.attrs ++ [
            {
              name = linkName;
              value = {
                kind = "p2p";
                endpoints = {
                  "${p.a}" = {
                    addr4 = addr4A;
                  }
                  // lib.optionalAttrs (v6pair.a != null) { addr6 = v6pair.a; };

                  "${p.b}" = {
                    addr4 = addr4B;
                  }
                  // lib.optionalAttrs (v6pair.b != null) { addr6 = v6pair.b; };
                };
              };
            }
          ];
        };

      res = builtins.foldl' step {
        idx = 0;
        used = [ ];
        attrs = [ ];
      } ps;

    in
    lib.listToAttrs res.attrs;
}
