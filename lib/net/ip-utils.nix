{ lib }:

let
  splitRaw = s: lib.splitString "/" (toString s);

  isIPv6 = s: lib.hasInfix ":" (toString s);

  ensureCidr =
    cidr:
    let
      parts = splitRaw cidr;
    in
    if builtins.length parts == 2 then
      cidr
    else if builtins.length parts == 1 then
      let
        ip = builtins.elemAt parts 0;
      in
      if isIPv6 ip then "${ip}/128" else "${ip}/32"
    else
      throw "ip-utils: invalid CIDR '${toString cidr}'";

  splitCidr =
    cidr:
    let
      fixed = ensureCidr cidr;
      parts = splitRaw fixed;
    in
    {
      ip = builtins.elemAt parts 0;
      prefix = lib.toInt (builtins.elemAt parts 1);
    };

  stripMask =
    s:
    let
      parts = splitRaw s;
    in
    if builtins.length parts == 0 then toString s else builtins.elemAt parts 0;

  parseOctet =
    s:
    let
      n = lib.toInt s;
    in
    if n < 0 || n > 255 then throw "ip-utils: invalid IPv4 octet '${s}'" else n;

  parseIPv4 =
    s:
    let
      parts = lib.splitString "." (toString s);
    in
    if builtins.length parts != 4 then
      throw "ip-utils: invalid IPv4 address '${toString s}'"
    else
      map parseOctet parts;

  ipv4ToInt =
    segs:
    (((builtins.elemAt segs 0) * 256 + builtins.elemAt segs 1) * 256 + builtins.elemAt segs 2) * 256
    + builtins.elemAt segs 3;

  intToIPv4 =
    n:
    let
      o0 = builtins.div n (256 * 256 * 256);
      r0 = n - o0 * 256 * 256 * 256;
      o1 = builtins.div r0 (256 * 256);
      r1 = r0 - o1 * 256 * 256;
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

  hasPrefixLength =
    cidr: want:
    let
      c = splitCidr cidr;
    in
    c.prefix == want;

in
{
  inherit
    splitCidr
    stripMask
    parseOctet
    parseIPv4
    ipv4ToInt
    intToIPv4
    hasPrefixLength
    ;
}
