{ lib ? (import <nixpkgs> { }).lib }:
import ./src { inherit lib; }
