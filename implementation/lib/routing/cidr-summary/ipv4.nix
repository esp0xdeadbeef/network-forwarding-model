{ lib, self ? { outPath = ./.; }, ... }:

let
  ip = import (self.outPath + "/implementation/lib/net/ip-utils.nix") { inherit lib self; };
  common = import (self.outPath + "/implementation/lib/routing/cidr-summary/common.nix") { inherit lib self; };

  inherit (common) floorLog2 mod pow2;

  cidrRange =
    cidr:
    let
      c = ip.splitCidr cidr;
      baseRaw = ip.ipv4ToInt (ip.parseIPv4 c.ip);
      size = pow2 (32 - c.prefix);
      base = (builtins.div baseRaw size) * size;
    in
    {
      start = base;
      end = base + size - 1;
      prefix = c.prefix;
    };

  mergeRanges =
    ranges:
    let
      sorted = lib.sort (a: b: a.start < b.start) ranges;
      step =
        acc: r:
        if acc == [ ] then
          [ r ]
        else
          let
            last = lib.last acc;
            rest = lib.take ((builtins.length acc) - 1) acc;
          in
          if r.start <= (last.end + 1) then
            rest
            ++ [
              (
                last
                // {
                  end = if r.end > last.end then r.end else last.end;
                }
              )
            ]
          else
            acc ++ [ r ];
    in
    builtins.foldl' step [ ] sorted;

  rangeToCidrs =
    start: end:
    let
      go =
        cur: acc:
        if cur > end then
          acc
        else
          let
            tz =
              if cur == 0 then
                32
              else
                let
                  goT =
                    x: count:
                    if count >= 32 || (mod x 2) != 0 then count else goT (builtins.div x 2) (count + 1);
                in
                goT cur 0;
            remain = end - cur + 1;
            fitBits = floorLog2 remain;
            blockBits = if tz < fitBits then tz else fitBits;
            size = pow2 blockBits;
            prefixLen = 32 - blockBits;
            blockEnd = cur + size - 1;
            item = "${ip.intToIPv4 cur}/${toString prefixLen}";
          in
          if blockEnd == end then acc ++ [ item ] else go (blockEnd + 1) (acc ++ [ item ]);
    in
    go start [ ];

  summarize =
    cidrs:
    let
      ranges = map cidrRange cidrs;
      merged = mergeRanges ranges;
    in
    lib.concatMap (r: rangeToCidrs r.start r.end) merged;

in
{
  inherit summarize;
}
