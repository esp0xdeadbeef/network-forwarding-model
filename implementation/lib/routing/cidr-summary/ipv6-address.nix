{ lib, ... }:

let
  haveNetwork = (lib ? network) && (lib.network ? ipv6) && (lib.network.ipv6 ? fromString);
  common = import ./common.nix { inherit lib; };

  inherit (common) mod pow2;

  ipv6Lib =
    if haveNetwork then
      lib.network.ipv6
    else
      throw "routing(cidr-summary): missing lib.network.ipv6 from nixpkgs-network";

  parse =
    value:
    let
      parsed = builtins.tryEval (ipv6Lib.fromString (toString value));
    in
    if parsed.success then
      parsed.value
    else
      throw "routing(cidr-summary): invalid IPv6 CIDR '${toString value}'";

  zpad =
    w: s:
    let
      len = builtins.stringLength s;
      zeros = builtins.concatStringsSep "" (builtins.genList (_: "0") (lib.max 0 (w - len)));
    in
    zeros + s;

  render = segs: lib.concatStringsSep ":" (map (x: zpad 4 (lib.toLower (lib.trivial.toHexString x))) segs);

  parseExpanded =
    value:
    let
      parts = lib.splitString "/" (toString value);
      ipText = builtins.elemAt parts 0;
      prefixText = if builtins.length parts > 1 then builtins.elemAt parts 1 else "128";
      segments = lib.splitString ":" ipText;
    in
    if builtins.length segments != 8 || lib.hasInfix "::" ipText then
      null
    else
      {
        address = map (segment: lib.fromHexString segment) segments;
        prefix = lib.toInt prefixText;
      };

  firstForPrefix =
    segs: prefixLen:
    let
      full = builtins.div prefixLen 16;
      rem = mod prefixLen 16;
    in
    builtins.genList
      (
        i:
        let
          seg = builtins.elemAt segs i;
        in
        if i < full then
          seg
        else if i == full && rem > 0 then
          (builtins.div seg (pow2 (16 - rem))) * (pow2 (16 - rem))
        else
          0
      )
      8;

  lastForPrefix =
    segs: prefixLen:
    let
      full = builtins.div prefixLen 16;
      rem = mod prefixLen 16;
    in
    builtins.genList
      (
        i:
        let
          seg = builtins.elemAt segs i;
        in
        if i < full then
          seg
        else if i == full && rem > 0 then
          ((builtins.div seg (pow2 (16 - rem))) * (pow2 (16 - rem))) + (pow2 (16 - rem)) - 1
        else
          65535
      )
      8;

in
{
  inherit
    firstForPrefix
    ipv6Lib
    lastForPrefix
    parse
    parseExpanded
    render
    ;
}
