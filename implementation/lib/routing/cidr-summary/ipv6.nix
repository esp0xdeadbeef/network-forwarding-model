{ lib, self ? { outPath = ./.; }, ... }:

let
  common = import (self.outPath + "/implementation/lib/routing/cidr-summary/common.nix") { inherit lib self; };
  address = import (self.outPath + "/implementation/lib/routing/cidr-summary/ipv6-address.nix") { inherit lib self; };

  inherit (common) mod;

  compare =
    a: b:
    let
      go =
        i:
        if i >= 8 then
          0
        else
          let
            av = builtins.elemAt a i;
            bv = builtins.elemAt b i;
          in
          if av < bv then -1 else if av > bv then 1 else go (i + 1);
    in
    go 0;

  lt = a: b: (compare a b) < 0;
  le = a: b: (compare a b) <= 0;
  eq = a: b: (compare a b) == 0;
  max = a: b: if lt a b then b else a;

  inc =
    segs:
    let
      go =
        i: carry: acc:
        if i < 0 then
          acc
        else
          let
            sum = (builtins.elemAt segs i) + carry;
          in
          go (i - 1) (builtins.div sum 65536) ([ (mod sum 65536) ] ++ acc);
    in
    go 7 1 [ ];

  allZero = builtins.genList (_: 0) 8;
  allOnes = builtins.genList (_: 65535) 8;
  isDefaultRoute = cidr: builtins.match ".*/0" (toString cidr) != null;

  cidrRange =
    cidr:
    if isDefaultRoute cidr then
      {
        start = allZero;
        end = allOnes;
        prefix = 0;
      }
    else
      let
        parsed = address.parse cidr;
      in
      {
        start = (address.ipv6Lib.firstAddress parsed)._address;
        end = (address.ipv6Lib.lastAddress parsed)._address;
        prefix = parsed.prefixLength;
      };

  mergeRanges =
    ranges:
    let
      sorted = lib.sort (a: b: lt a.start b.start) ranges;
      step =
        acc: r:
        if acc == [ ] then
          [ r ]
        else
          let
            last = lib.last acc;
            rest = lib.take ((builtins.length acc) - 1) acc;
            lastEndNext = inc last.end;
          in
          if le r.start lastEndNext || eq r.start lastEndNext then
            rest ++ [ (last // { end = max last.end r.end; }) ]
          else
            acc ++ [ r ];
    in
    builtins.foldl' step [ ] sorted;

  tz16 =
    n:
    let
      go =
        x: count:
        if count >= 16 then 16 else if (mod x 2) != 0 then count else go (builtins.div x 2) (count + 1);
    in
    if n == 0 then 16 else go n 0;

in
rec {
  inherit
    eq
    inc
    le
    lt
    tz16
    ;

  toStringV6 = address.render;

  prefixEnd =
    start: prefixLen:
    if prefixLen == 0 then
      allOnes
    else
      (address.ipv6Lib.lastAddress (address.parse "${address.render start}/${toString prefixLen}"))._address;

  rangeToCidrs = import (self.outPath + "/implementation/lib/routing/cidr-summary/ipv6-range-to-cidrs.nix") {
    inherit lib;
    ipv6 = {
      inherit
        eq
        inc
        le
        lt
        prefixEnd
        toStringV6
        tz16
        ;
    };
  };

  summarize =
    cidrs:
    let
      ranges = map cidrRange cidrs;
      merged = mergeRanges ranges;
    in
    lib.concatMap (
      r: if eq r.start allZero && eq r.end allOnes then [ "::/0" ] else rangeToCidrs r.start r.end
    ) merged;
}
