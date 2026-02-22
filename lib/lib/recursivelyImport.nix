{ nix }:
if nix ? lib then
  nix.lib
else if nix ? inputs && nix.inputs ? nixpkgs && nix.inputs.nixpkgs ? lib then
  nix.inputs.nixpkgs.lib
else
  throw "could not resolve nixpkgs lib"
