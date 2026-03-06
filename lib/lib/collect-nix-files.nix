{ lib }:
list:
builtins.filter
  (x: !builtins.isPath x || lib.hasSuffix ".nix" (toString x))
  (lib.concatMap (
    x:
    if builtins.isPath x && builtins.readFileType x == "directory" then
      lib.filesystem.listFilesRecursive x
    else
      [ x ]
  ) list)
