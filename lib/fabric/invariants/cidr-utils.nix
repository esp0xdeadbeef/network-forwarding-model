# ./lib/fabric/invariants/cidr-utils.nix
# IPv4 uses 32-bit ints; IPv6 uses fixed-width expanded strings.
# Avoids builtins.bitShiftLeft (not available on older Nix).
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

  # ---------------- IPv4 helpers ----------------
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

  pow2Small =
    n:
    builtins.foldl' (acc: _: acc * 2) 1 (lib.range 1 n);

  # ---------------- IPv6 helpers (no int128, no bitShiftLeft) ----------------
  haveNetwork = (lib ? network) && (lib.network ? ipv6) && (lib.network.ipv6 ? fromString);

  ipv6Parse =
    s:
    if haveNetwork then
      lib.network.ipv6.fromString (toString s)
    else
      throw "cidr-utils: missing lib.network.ipv6.fromString (use flake patched nixpkgs-network)";

  zpad =
    w: s:
    let
      len = builtins.stringLength s;
      zeros = builtins.concatStringsSep "" (builtins.genList (_: "0") (lib.max 0 (w - len)));
    in
    zeros + s;

  toHexLower = n: lib.toLower (lib.trivial.toHexString n);

  v6ToFixed =
    segs:
    lib.concatStringsSep ":" (map (x: zpad 4 (toHexLower x)) segs);

  v6FirstLast =
    { segs, prefix }:
    let
      apply =
        { isLast }:
        builtins.genList
          (i:
            let
              rem0 = prefix - (i * 16);
              rem =
                if rem0 < 0 then 0
                else if rem0 > 16 then 16
                else rem0;

              v = builtins.elemAt segs i;

              ones =
                if rem == 0 then
                  0
                else
                  (pow2Small rem) - 1;

              # left shift without bitShiftLeft
              maskNet =
                if rem == 0 then
                  0
                else
                  ones * (pow2Small (16 - rem));

              base = builtins.bitAnd v maskNet;

              hostMask =
                if rem == 16 then
                  0
                else
                  (pow2Small (16 - rem)) - 1;

              withHost =
                if isLast then
                  builtins.bitOr base hostMask
                else
                  base;

              fillAll =
                if rem == 16 then
                  v
                else if rem == 0 then
                  (if isLast then 65535 else 0)
                else
                  withHost;
            in
            fillAll)
          8;

      firstSegs = apply { isLast = false; };
      lastSegs = apply { isLast = true; };
    in
    {
      first = v6ToFixed firstSegs;
      last = v6ToFixed lastSegs;
    };

  cidrRange =
    cidr:
    let
      c = splitCidr cidr;
    in
    if lib.hasInfix "." c.ip then
      let
        base = v4ToInt (parseV4 c.ip);
        size = pow2Small (32 - c.prefix);
      in
      {
        family = 4;
        start = base;
        end = base + size - 1;
      }
    else
      let
        parsed = ipv6Parse "${toString c.ip}/${toString c.prefix}";
        segs = parsed._address or (throw "cidr-utils: lib.network.ipv6.fromString missing _address");
        fl = v6FirstLast { inherit segs; prefix = c.prefix; };
      in
      {
        family = 6;
        start = fl.first;
        end = fl.last;
      };

in
{
  inherit cidrRange;
}
