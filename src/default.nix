{ lib }:
{ input }:

(import ./main.nix { inherit lib; }) { inherit input; }
