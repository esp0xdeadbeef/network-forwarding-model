{ lib, topo }:

let
  routes = import (self.outPath + "/lib/model/routes.nix") { inherit lib self; };

  ifaceRoutes = routes.ifaceRoutes;

  collect = _: link: builtins.mapAttrs (_: ep: ifaceRoutes ep) (link.endpoints or { });
in
builtins.foldl' (
  acc: linkName:
  let
    perLink = collect linkName topo.links.${linkName};
  in
  acc // builtins.mapAttrs (n: r: (acc.${n} or [ ]) ++ r) perLink
) { } (builtins.attrNames (topo.links or { }))
