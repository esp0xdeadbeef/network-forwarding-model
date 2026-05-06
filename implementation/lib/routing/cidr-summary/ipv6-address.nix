{ lib, ... }:

let
  haveNetwork = (lib ? network) && (lib.network ? ipv6) && (lib.network.ipv6 ? fromString);

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

in
{
  inherit ipv6Lib parse render;
}
