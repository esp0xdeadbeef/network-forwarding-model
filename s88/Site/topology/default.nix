{ lib, self ? { outPath = ./.; }, ... }:
(import ./build.nix { inherit lib self; })
