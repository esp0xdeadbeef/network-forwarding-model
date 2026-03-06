# ./src/util/derive.nix
{ lib }:

let
  split = sep: s: lib.splitString sep (toString s);
  stripMask = cidr:
    let parts = split "/" cidr;
    in if parts == [ ] then toString cidr else builtins.head parts;
in
{
  roleForUnit =
    n:
    let s = toString n;
    in
    if lib.hasInfix "upstream-selector" s || lib.hasInfix "upstream_selector" s then "upstream-selector"
    else if lib.hasInfix "policy" s then "policy"
    else if lib.hasInfix "access" s then "access"
    else if lib.hasInfix "core" s then "core"
    else null;

  tenantV4BaseFrom =
    tenant4:
    let octs = split "." (stripMask tenant4);
    in
    if builtins.length octs == 4 then
      lib.concatStringsSep "." [ (builtins.elemAt octs 0) (builtins.elemAt octs 1) ]
    else
      throw "network-solver: cannot derive tenantV4Base";

  ulaPrefixFrom =
    tenant6:
    let hextets = split ":" (stripMask tenant6);
    in
    if builtins.length hextets >= 3 then
      lib.concatStringsSep ":" [ (builtins.elemAt hextets 0) (builtins.elemAt hextets 1) (builtins.elemAt hextets 2) ]
    else
      throw "network-solver: cannot derive ulaPrefix";
}
