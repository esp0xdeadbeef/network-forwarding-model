{ lib ? (import <nixpkgs> { }).lib }:
{ input }:

(import ./src { inherit lib; }) { inherit input; }
