{ lib ? (import <nixpkgs> { }).lib, self ? { outPath = ./.; } }:
import ./s88/build.nix { inherit lib self; }
