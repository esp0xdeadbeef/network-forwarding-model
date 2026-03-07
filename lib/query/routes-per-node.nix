{ topo }:

let
  routes = import ../model/routes.nix { lib = import <nixpkgs/lib>; };

  ifaceRoutes = routes.ifaceRoutes;

  collect = linkName: link: builtins.mapAttrs (_: ep: ifaceRoutes ep) (link.endpoints or { });
in
builtins.foldl' (
  acc: linkName:
  let
    perLink = collect linkName topo.links.${linkName};
  in
  acc // builtins.mapAttrs (n: r: (acc.${n} or [ ]) ++ r) perLink
) { } (builtins.attrNames topo.links)
