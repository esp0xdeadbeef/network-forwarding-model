{ lib, ... }:

let
  pow2 = n: builtins.foldl' (acc: _: acc * 2) 1 (lib.range 1 n);

  mod = a: b: a - (builtins.div a b) * b;

  floorLog2 =
    n:
    let
      go = v: acc: if v < 2 then acc else go (builtins.div v 2) (acc + 1);
    in
    if n <= 0 then 0 else go n 0;

in
{
  inherit
    floorLog2
    mod
    pow2
    ;
}
