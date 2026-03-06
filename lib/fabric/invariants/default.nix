# ./lib/fabric/invariants/default.nix
{ lib }:

let
  collect = import ../../lib/collect-nix-files.nix { inherit lib; };

  modules =
    map
      (p: import p { inherit lib; })
      (lib.filter
        (p:
          baseNameOf p != "default.nix"
          && (builtins.readDir (builtins.dirOf p)).${baseNameOf p} == "regular")
        (collect [ ./. ]));

  runSite =
    site:
    lib.forEach modules (m:
      if !(m ? check) then
        true
      else
        let args = builtins.functionArgs m.check;
        in
        if args ? site then m.check { inherit site; }
        else if args ? nodes then m.check { nodes = site.nodes or { }; }
        else throw ''
          invariant loader error:

          The invariant '${toString m}' defines `check` but does not accept
          `{ site }` nor `{ nodes }`.

          Valid signatures:
            check = { site }: ...
            check = { nodes }: ...
        '');

in
{
  checkSite = { site }: builtins.deepSeq (runSite site) true;
  checkAll = { sites }: builtins.deepSeq (lib.forEach modules (m: if m ? checkAll then m.checkAll { inherit sites; } else true)) true;
}
