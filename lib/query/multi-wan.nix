{ lib, routed }:

let
  wans = lib.filterAttrs (_: l: (l.kind or null) == "wan") routed.links;
in
{
  count = lib.length (lib.attrNames wans);
  links = wans;
}
