{ lib }:

let
  split = sep: s: lib.splitString sep (toString s);
  join  = sep: xs: lib.concatStringsSep sep xs;

  stripMask =
    cidr:
    let parts = split "/" cidr;
    in if parts == [ ] then toString cidr else builtins.elemAt parts 0;
in {
  roleForUnit =
    n:
    let
      s = toString n;
      has = pat: lib.hasInfix pat s;
    in
    if has "upstream-selector" || has "upstream_selector" then
      "upstream-selector"
    else if has "policy" then
      "policy"
    else if has "access" then
      "access"
    else if has "core" then
      "core"
    else
      null;

  tenantV4BaseFrom =
    tenant4:
    let
      ip = stripMask tenant4;
      octs = split "." ip;
    in
    if builtins.length octs == 4 then
      join "." (builtins.genList (i: builtins.elemAt octs i) 2)
    else
      throw "network-solver: cannot derive tenantV4Base";

  ulaPrefixFrom =
    tenant6:
    let
      ip = stripMask tenant6;
      hextets = split ":" ip;
    in
    if builtins.length hextets >= 3 then
      join ":" (builtins.genList (i: builtins.elemAt hextets i) 3)
    else
      throw "network-solver: cannot derive ulaPrefix";
}
