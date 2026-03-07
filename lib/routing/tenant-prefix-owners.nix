{ lib }:

let
  helpers = import ./static-helpers.nix { inherit lib; };

  build =
    topo:
    let
      nodes = topo.nodes or { };
      nodeNames = lib.sort (a: b: a < b) (builtins.attrNames nodes);

      entries = lib.concatMap (
        nodeName:
        map (
          e:
          e
          // {
            owner = nodeName;
          }
        ) (helpers.prefixEntriesFromNetworks nodes.${nodeName})
      ) nodeNames;

      step =
        acc: e:
        let
          k = "${toString e.family}|${e.dst}";
        in
        if acc ? "${k}" then
          let
            prev = acc.${k};
          in
          if prev.owner == e.owner then
            acc
          else
            throw "tenant-prefix-owners: prefix '${e.dst}' has multiple owners ('${prev.owner}' via '${prev.netName}' and '${e.owner}' via '${e.netName}')"
        else
          acc
          // {
            "${k}" = {
              family = e.family;
              dst = e.dst;
              owner = e.owner;
              netName = e.netName or null;
            };
          };

    in
    builtins.foldl' step { } entries;

in
{
  inherit build;
}
