{ lib }:
{
  requireAttr = path: v:
    if v == null then throw "network-solver: missing required attribute: ${path}" else v;

  safeHead = what: xs:
    if builtins.isList xs && xs != [ ] then builtins.head xs
    else throw "network-solver: expected at least one ${what}";

  split = sep: s: lib.splitString sep (toString s);
}
