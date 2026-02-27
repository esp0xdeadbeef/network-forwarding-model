{ lib }:

let
  split = sep: s: lib.splitString sep (toString s);
in {
  requireAttr =
    path: v:
    if v == null then
      throw "network-solver: missing required attribute: ${path}"
    else
      v;

  safeHead =
    what: xs:
    if builtins.isList xs && builtins.length xs > 0 then
      builtins.elemAt xs 0
    else
      throw "network-solver: expected at least one ${what}";

  split = split;
}
