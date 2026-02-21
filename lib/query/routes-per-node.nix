{ topo }:

let
  collect =
    linkName: link:
    builtins.mapAttrs (node: ep: (ep.routes4 or [ ]) ++ (ep.routes6 or [ ])) (link.endpoints or { });
in
builtins.foldl' (
  acc: linkName:
  let
    perLink = collect linkName topo.links.${linkName};
  in
  acc // builtins.mapAttrs (n: r: (acc.${n} or [ ]) ++ r) perLink
) { } (builtins.attrNames topo.links)
