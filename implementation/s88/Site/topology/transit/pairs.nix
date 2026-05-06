{ lib, ... }:

let
  sortedPair =
    a: b:
    if a < b then
      {
        left = a;
        right = b;
      }
    else
      {
        left = b;
        right = a;
      };

in
{
  inherit sortedPair;

  pairKey =
    a: b:
    let
      p = sortedPair a b;
    in
    "${p.left}|${p.right}";

  looksLikeStableLinkId = x: builtins.isString x && lib.hasPrefix "link::" (toString x);
}
