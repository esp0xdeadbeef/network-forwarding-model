{ lib }:

let

  collect = import ../../lib/collect-nix-files.nix { inherit lib; };

  files = lib.filter (p: baseNameOf p != "default.nix") (collect [ ./. ]);

  isRegular =
    p:
    let
      dir = builtins.readDir (builtins.dirOf p);
      bn = baseNameOf p;
    in
    (dir ? "${bn}") && dir."${bn}" == "regular";

  modules = map (p: import p { inherit lib; }) (lib.filter isRegular files);

  callCheckSite =
    site:
    lib.forEach modules (
      m:
      if m ? check then
        let
          args = builtins.functionArgs m.check;
        in
        if args ? site then
          m.check { inherit site; }
        else if args ? nodes then
          m.check { nodes = site.nodes or { }; }
        else
          throw ''
            invariant loader error:

            The invariant '${toString m}' defines `check` but does not accept
            `{ site }` nor `{ nodes }`.

            Valid signatures:
              check = { site }: ...
              check = { nodes }: ...

            This invariant is currently being skipped silently.
          ''
      else
        true
    );

  callCheckAll =
    sites: lib.forEach modules (m: if m ? checkAll then m.checkAll { inherit sites; } else true);

in
{
  checkSite = { site }: builtins.deepSeq (callCheckSite site) true;

  checkAll = { sites }: builtins.deepSeq (callCheckAll sites) true;
}
