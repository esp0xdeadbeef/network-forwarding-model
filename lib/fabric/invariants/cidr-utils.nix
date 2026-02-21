{ lib }:

let
  splitCidr =
    cidr:
    let
      parts = lib.splitString "/" (toString cidr);
    in
    if builtins.length parts != 2 then
      throw "cidr-utils: invalid CIDR '${toString cidr}'"
    else
      {
        ip = builtins.elemAt parts 0;
        prefix = lib.toInt (builtins.elemAt parts 1);
      };

  parseOctet =
    s:
    let
      n = lib.toInt s;
    in
    if n < 0 || n > 255 then throw "cidr-utils: bad IPv4 octet '${s}'" else n;

  parseV4 =
    s:
    let
      p = lib.splitString "." s;
    in
    if builtins.length p != 4 then throw "cidr-utils: bad IPv4 '${s}'" else map parseOctet p;

  v4ToInt =
    o:
    (((builtins.elemAt o 0) * 256 + (builtins.elemAt o 1)) * 256 + (builtins.elemAt o 2)) * 256
    + (builtins.elemAt o 3);

  pow2 = n: if n <= 0 then 1 else 2 * pow2 (n - 1);

  hexToInt = s: if s == "" then 0 else (builtins.fromTOML "x = 0x${s}").x;

  parseHextet =
    s:
    let
      n = hexToInt s;
    in
    if n < 0 || n > 65535 then throw "cidr-utils: bad IPv6 hextet '${s}'" else n;

  expandIPv6 =
    s:
    let
      parts = lib.splitString "::" s;
    in
    if builtins.length parts == 1 then
      map parseHextet (lib.splitString ":" s)
    else if builtins.length parts == 2 then
      let
        left = if builtins.elemAt parts 0 == "" then [ ] else lib.splitString ":" (builtins.elemAt parts 0);
        right =
          if builtins.elemAt parts 1 == "" then [ ] else lib.splitString ":" (builtins.elemAt parts 1);
        missing = 8 - (builtins.length left + builtins.length right);
      in
      (map parseHextet left) ++ (builtins.genList (_: 0) missing) ++ (map parseHextet right)
    else
      throw "cidr-utils: bad IPv6 '${s}'";

  v6ToInt128 = segs: builtins.foldl' (acc: x: acc * 65536 + x) 0 segs;

  cidrRange =
    cidr:
    let
      c = splitCidr cidr;
    in
    if lib.hasInfix "." c.ip then
      let
        base = v4ToInt (parseV4 c.ip);
        size = pow2 (32 - c.prefix);
      in
      {
        family = 4;
        start = base;
        end = base + size - 1;
      }
    else
      let
        segs = expandIPv6 c.ip;
        base = v6ToInt128 segs;
        size = pow2 (128 - c.prefix);
      in
      {
        family = 6;
        start = base;
        end = base + size - 1;
      };

in
{
  inherit cidrRange;
}
