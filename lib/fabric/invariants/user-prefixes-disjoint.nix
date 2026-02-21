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
    if n < 0 || n > 255 then throw "invariants(user-prefixes): bad IPv4 octet '${s}'" else n;

  parseV4 =
    s:
    let
      p = lib.splitString "." s;
    in
    if builtins.length p != 4 then
      throw "invariants(user-prefixes): bad IPv4 '${s}'"
    else
      map parseOctet p;

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
    if n < 0 || n > 65535 then throw "invariants(user-prefixes): bad IPv6 hextet '${s}'" else n;

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
      throw "invariants(user-prefixes): bad IPv6 '${s}'";

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

  overlaps = a: b: a.family == b.family && !(a.end < b.start || b.end < a.start);

in
{
  check =
    { nodes }:
    let
      entries = lib.concatMap (
        name:
        let
          n = nodes.${name};
          nets = n.networks or null;
        in
        if nets == null then
          [ ]
        else
          lib.flatten [
            (lib.optional (nets ? ipv4) {
              cidr = nets.ipv4;
              owner = "node '${name}' ipv4";
            })
            (lib.optional (nets ? ipv6) {
              cidr = nets.ipv6;
              owner = "node '${name}' ipv6";
            })
          ]
      ) (builtins.attrNames nodes);

      withRanges = map (e: e // { range = cidrRange e.cidr; }) entries;

      pairs = lib.concatMap (
        i:
        let
          a = builtins.elemAt withRanges i;
        in
        map (
          j:
          let
            b = builtins.elemAt withRanges j;
          in
          {
            inherit a b;
          }
        ) (lib.range (i + 1) (builtins.length withRanges - 1))
      ) (lib.range 0 (builtins.length withRanges - 2));

      checked = lib.all (
        p:
        assert_ (!(overlaps p.a.range p.b.range))
          "invariants(user-prefixes): overlapping user prefixes '${p.a.cidr}' (${p.a.owner}) and '${p.b.cidr}' (${p.b.owner})"
      ) pairs;
    in
    builtins.deepSeq checked true;
}
