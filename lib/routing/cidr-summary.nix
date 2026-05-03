{ lib }:

let
  ip = import ../net/ip-utils.nix { inherit lib; };
  prefix = import ../model/prefix-utils.nix { inherit lib; };

  pow2 = n: builtins.foldl' (acc: _: acc * 2) 1 (lib.range 1 n);

  mod = a: b: a - (builtins.div a b) * b;

  hexToInt = s: if s == "" then 0 else (builtins.fromTOML "x = 0x${s}").x;

  parseHextet =
    s:
    let
      n = hexToInt s;
    in
    if n < 0 || n > 65535 then throw "routing(static-helpers): invalid IPv6 hextet '${s}'" else n;

  expandIPv6 =
    s:
    let
      parts = lib.splitString "::" s;
    in
    if builtins.length parts == 1 then
      let
        hs = lib.splitString ":" s;
      in
      if builtins.length hs != 8 then
        throw "routing(static-helpers): invalid IPv6 address '${s}'"
      else
        map parseHextet hs
    else if builtins.length parts == 2 then
      let
        left = if builtins.elemAt parts 0 == "" then [ ] else lib.splitString ":" (builtins.elemAt parts 0);

        right =
          if builtins.elemAt parts 1 == "" then [ ] else lib.splitString ":" (builtins.elemAt parts 1);

        missing = 8 - (builtins.length left + builtins.length right);
      in
      if missing < 0 then
        throw "routing(static-helpers): invalid IPv6 address '${s}'"
      else
        (map parseHextet left) ++ (builtins.genList (_: 0) missing) ++ (map parseHextet right)
    else
      throw "routing(static-helpers): invalid IPv6 address '${s}'";

  zpad =
    w: s:
    let
      len = builtins.stringLength s;
      zeros = builtins.concatStringsSep "" (builtins.genList (_: "0") (lib.max 0 (w - len)));
    in
    zeros + s;

  toHexLower = n: lib.toLower (lib.trivial.toHexString n);

  ipv6ToString = segs: lib.concatStringsSep ":" (map (x: zpad 4 (toHexLower x)) segs);

  applyPrefixV6 =
    {
      segs,
      prefix,
      isLast,
    }:
    builtins.genList (
      i:
      let
        rem0 = prefix - (i * 16);
        rem =
          if rem0 < 0 then
            0
          else if rem0 > 16 then
            16
          else
            rem0;

        v = builtins.elemAt segs i;

        ones = if rem == 0 then 0 else (pow2 rem) - 1;
        maskNet = if rem == 0 then 0 else ones * (pow2 (16 - rem));
        base = builtins.bitAnd v maskNet;
        hostMask = if rem == 16 then 0 else (pow2 (16 - rem)) - 1;
        withHost = if isLast then builtins.bitOr base hostMask else base;
      in
      if rem == 16 then
        v
      else if rem == 0 then
        if isLast then 65535 else 0
      else
        withHost
    ) 8;

  cidrRange4 =
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

  cidrRange6 =
    cidr:
    let
      c = ip.splitCidr cidr;
      segs = expandIPv6 c.ip;
    in
    {
      start = applyPrefixV6 {
        inherit segs;
        prefix = c.prefix;
        isLast = false;
      };
      end = applyPrefixV6 {
        inherit segs;
        prefix = c.prefix;
        isLast = true;
      };
      prefix = c.prefix;
    };

  cmpSegs =
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
          if av < bv then
            -1
          else if av > bv then
            1
          else
            go (i + 1);
    in
    go 0;

  ltSegs = a: b: (cmpSegs a b) < 0;
  leSegs = a: b: (cmpSegs a b) <= 0;
  eqSegs = a: b: (cmpSegs a b) == 0;
  maxSegs = a: b: if ltSegs a b then b else a;

  incSegs =
    segs:
    let
      go =
        i: carry: acc:
        if i < 0 then
          acc
        else
          let
            cur = builtins.elemAt segs i;
            sum = cur + carry;
            newVal = mod sum 65536;
            newCarry = builtins.div sum 65536;
          in
          go (i - 1) newCarry ([ newVal ] ++ acc);
    in
    go 7 1 [ ];

  tz16 =
    n:
    let
      go =
        x: count:
        if count >= 16 then
          16
        else if (mod x 2) != 0 then
          count
        else
          go (builtins.div x 2) (count + 1);
    in
    if n == 0 then 16 else go n 0;

  trailingZerosLimitedV6 =
    segs: bits:
    let
      go =
        i: acc:
        if i < 0 || acc >= bits then
          if acc > bits then bits else acc
        else
          let
            seg = builtins.elemAt segs i;
            tz = tz16 seg;
            acc1 = acc + tz;
          in
          if tz < 16 then if acc1 > bits then bits else acc1 else go (i - 1) acc1;
    in
    go 7 0;

  floorLog2 =
    n:
    let
      go = v: acc: if v < 2 then acc else go (builtins.div v 2) (acc + 1);
    in
    if n <= 0 then 0 else go n 0;

  mergeRanges4 =
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

  mergeRanges6 =
    ranges:
    let
      sorted = lib.sort (a: b: ltSegs a.start b.start) ranges;
      step =
        acc: r:
        if acc == [ ] then
          [ r ]
        else
          let
            last = lib.last acc;
            rest = lib.take ((builtins.length acc) - 1) acc;
            lastEndNext = incSegs last.end;
            touches = leSegs r.start lastEndNext || eqSegs r.start lastEndNext;
          in
          if touches then
            rest
            ++ [
              (
                last
                // {
                  end = maxSegs last.end r.end;
                }
              )
            ]
          else
            acc ++ [ r ];
    in
    builtins.foldl' step [ ] sorted;

  rangeToCidrs4 =
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
                  goT = x: count: if count >= 32 || (mod x 2) != 0 then count else goT (builtins.div x 2) (count + 1);
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

  prefixEnd6 =
    start: prefixLen:
    applyPrefixV6 {
      segs = start;
      prefix = prefixLen;
      isLast = true;
    };

  rangeToCidrs6 =
    start: end:
    let
      chooseBlockBits =
        cur:
        let
          aligned = trailingZerosLimitedV6 cur 128;
          candidates = map (x: aligned - x) (lib.range 0 aligned);
          usable = lib.filter (
            blockBits:
            let
              prefixLen = 128 - blockBits;
              blockEnd = prefixEnd6 cur prefixLen;
            in
            leSegs blockEnd end
          ) candidates;
        in
        if usable == [ ] then 0 else builtins.head usable;

      go =
        cur: acc:
        if ltSegs end cur then
          acc
        else
          let
            blockBits = chooseBlockBits cur;
            prefixLen = 128 - blockBits;
            blockEnd = prefixEnd6 cur prefixLen;
            item = "${ipv6ToString cur}/${toString prefixLen}";
          in
          if eqSegs blockEnd end then acc ++ [ item ] else go (incSegs blockEnd) (acc ++ [ item ]);
    in
    go start [ ];

  summarizeCidrs =
    family: cidrs:
    if cidrs == [ ] then
      [ ]
    else if family == 4 then
      let
        ranges = map cidrRange4 cidrs;
        merged = mergeRanges4 ranges;
      in
      lib.concatMap (r: rangeToCidrs4 r.start r.end) merged
    else
      let
        ranges = map cidrRange6 cidrs;
        merged = mergeRanges6 ranges;
      in
      lib.concatMap (r: rangeToCidrs6 r.start r.end) merged;

in
{
  inherit summarizeCidrs;
}
