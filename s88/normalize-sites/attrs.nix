{ lib }:

let
  hasAttrPath =
    path: set:
    if path == [ ] then
      true
    else
      let
        key = builtins.head path;
      in
      builtins.isAttrs set && builtins.hasAttr key set && hasAttrPath (builtins.tail path) set.${key};

  getAttrPathOr =
    path: default: set:
    if path == [ ] then
      set
    else
      let
        key = builtins.head path;
      in
      if builtins.isAttrs set && builtins.hasAttr key set then
        getAttrPathOr (builtins.tail path) default set.${key}
      else
        default;

  mergeAttrs =
    left: right:
    if builtins.isAttrs left && builtins.isAttrs right then lib.recursiveUpdate left right else right;

in
{
  inherit
    getAttrPathOr
    hasAttrPath
    mergeAttrs
    ;
}
