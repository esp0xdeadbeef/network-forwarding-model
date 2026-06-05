{ lib, ipv6 }:

let
  trailingZerosLimited =
    segs: bits:
    let
      go =
        i: acc:
        if i < 0 || acc >= bits then
          if acc > bits then bits else acc
        else
          let
            tz = ipv6.tz16 (builtins.elemAt segs i);
            acc1 = acc + tz;
          in
          if tz < 16 then if acc1 > bits then bits else acc1 else go (i - 1) acc1;
    in
    go 7 0;

in
start: end:
let
  chooseBlockBits =
    cur:
    let
      aligned = trailingZerosLimited cur 128;
      candidates = map (x: aligned - x) (lib.range 0 aligned);
      usable = lib.filter (blockBits: ipv6.le (ipv6.prefixEnd cur (128 - blockBits)) end) candidates;
    in
    if usable == [ ] then 0 else builtins.head usable;

  go =
    cur: acc:
    if ipv6.lt end cur then
      acc
    else
      let
        blockBits = chooseBlockBits cur;
        prefixLen = 128 - blockBits;
        blockEnd = ipv6.prefixEnd cur prefixLen;
        item = "${ipv6.toStringV6 cur}/${toString prefixLen}";
      in
      if ipv6.eq blockEnd end then lib.reverseList ([ item ] ++ acc) else go (ipv6.inc blockEnd) ([ item ] ++ acc);
in
go start [ ]
