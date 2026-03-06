# ./lib/query/routes-per-node.nix
{ topo }:

let
  routesOf =
    ep:
    if ep ? routes && builtins.isAttrs ep.routes then
      (ep.routes.ipv4 or [ ]) ++ (ep.routes.ipv6 or [ ])
    else
      (ep.routes4 or [ ]) ++ (ep.routes6 or [ ]);

  collect =
    linkName: link:
    builtins.mapAttrs (_: ep: routesOf ep) (link.endpoints or { });
in
builtins.foldl' (
  acc: linkName:
  let
    perLink = collect linkName topo.links.${linkName};
  in
  acc // builtins.mapAttrs (n: r: (acc.${n} or [ ]) ++ r) perLink
) { } (builtins.attrNames topo.links)
