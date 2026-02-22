{ lib }:

let
  inherit (lib) concatMap hasSuffix;
  inherit (builtins) isPath filter readFileType;

  expandIfFolder =
    elem:
    if !isPath elem || readFileType elem != "directory" then
      [ elem ]
    else
      lib.filesystem.listFilesRecursive elem;

in
list:
filter

  (elem: !isPath elem || hasSuffix ".nix" (toString elem))

  (concatMap expandIfFolder list)
