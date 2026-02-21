{ lib }:

let
  nodeIndex =
    node: members:
    let
      go =
        i: xs:
        if xs == [ ] then
          -1
        else if lib.head xs == node then
          i
        else
          go (i + 1) (lib.tail xs);
    in
    go 0 members;

  digits = [
    "0"
    "1"
    "2"
    "3"
    "4"
    "5"
    "6"
    "7"
    "8"
    "9"
    "a"
    "b"
    "c"
    "d"
    "e"
    "f"
  ];

  toHex =
    n:
    let
      go =
        x:
        if x < 16 then
          [ (lib.elemAt digits x) ]
        else
          (go (builtins.div x 16)) ++ [ (lib.elemAt digits (x - (builtins.div x 16) * 16)) ];
    in
    builtins.concatStringsSep "" (go n);

  zpad =
    w: s:
    let
      len = builtins.stringLength s;
      zeros = builtins.concatStringsSep "" (builtins.genList (_: "0") (lib.max 0 (w - len)));
    in
    zeros + s;

  transitHextet =
    tvid:
    if tvid < 0 || tvid > 255 then
      throw "addressing: transit vlanId ${toString tvid} out of range (0..255)"
    else
      "ff${zpad 2 (toHex tvid)}";

  splitCidr =
    cidr:
    let
      parts = lib.splitString "/" cidr;
    in
    if builtins.length parts != 2 then
      throw "addressing: invalid CIDR '${cidr}'"
    else
      {
        ip = builtins.elemAt parts 0;
        prefixLength = lib.toInt (builtins.elemAt parts 1);
      };

  parseOctet =
    s:
    let
      n = lib.toInt s;
    in
    if n < 0 || n > 255 then throw "addressing: invalid IPv4 octet '${s}'" else n;

  parseIPv4 =
    s:
    let
      parts = lib.splitString "." s;
    in
    if builtins.length parts != 4 then
      throw "addressing: invalid IPv4 address '${s}'"
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

  hostCidr4 =
    hostIndex: cidr:
    let
      c = splitCidr cidr;
      baseInt = ipv4ToInt (parseIPv4 c.ip);
      addr = intToIPv4 (baseInt + hostIndex);
    in
    "${addr}/${toString c.prefixLength}";

  hexToInt = s: if s == "" then 0 else (builtins.fromTOML "x = 0x${s}").x;

  parseHextet =
    s:
    let
      n = hexToInt s;
    in
    if n < 0 || n > 65535 then throw "addressing: invalid IPv6 hextet '${s}'" else n;

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
        throw "addressing: invalid IPv6 address '${s}'"
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
        throw "addressing: invalid IPv6 address '${s}'"
      else
        (map parseHextet left) ++ (builtins.genList (_: 0) missing) ++ (map parseHextet right)
    else
      throw "addressing: invalid IPv6 address '${s}'";

  addHostToIPv6 =
    segs: hostIndex:
    let
      addRec =
        i: carry: acc:
        if i < 0 then
          acc
        else
          let
            idx = i;
            sum = (builtins.elemAt segs idx) + carry;
            newVal = sum - (builtins.div sum 65536) * 65536;
            newCarry = builtins.div sum 65536;
          in
          addRec (i - 1) newCarry ([ newVal ] ++ acc);
    in
    addRec 7 hostIndex [ ];

  ipv6ToString = segs: lib.concatStringsSep ":" (map (x: zpad 1 (toHex x)) segs);

  hostCidr6 =
    hostIndex: cidr:
    let
      c = splitCidr cidr;
      baseSegs = expandIPv6 c.ip;
      newSegs = addHostToIPv6 baseSegs hostIndex;
      addr = ipv6ToString newSegs;
    in
    "${addr}/${toString c.prefixLength}";

  hostCidr =
    hostIndex: cidr:
    if lib.hasInfix "." cidr then hostCidr4 hostIndex cidr else hostCidr6 hostIndex cidr;

in
{
  inherit transitHextet hostCidr;

  mkTenantV4 = { v4Base, vlanId }: hostCidr 1 "${v4Base}.${toString vlanId}.0/24";

  mkTenantV6 = { ulaPrefix, vlanId }: hostCidr 1 "${ulaPrefix}:${toString vlanId}::/64";

  mkP2P4 =
    {
      v4Base,
      vlanId,
      node,
      members,
    }:
    let
      idx = nodeIndex node members;
    in
    if idx < 0 || idx > 1 then
      throw "p2p requires exactly 2 members and node must be a member"
    else
      hostCidr (idx + 1) "${v4Base}.${toString vlanId}.0/31";

  mkP2P6 =
    {
      ulaPrefix,
      vlanId,
      node,
      members,
    }:
    let
      idx = nodeIndex node members;
      base = "${ulaPrefix}:${transitHextet vlanId}::/127";
    in
    if idx < 0 || idx > 1 then
      throw "p2p requires exactly 2 members and node must be a member"
    else
      hostCidr (idx + 1) base;
}
