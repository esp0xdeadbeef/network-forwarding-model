{ lib }:

let
  common = import ./common.nix { inherit lib; };

  ifaceKeys =
    x:
    if builtins.isAttrs x && x ? interfaces && builtins.isAttrs x.interfaces then
      builtins.attrNames x.interfaces
    else
      [ ];

  mkEntries =
    {
      siteName,
      nodeName,
      node,
    }:
    let
      top = map (k: {
        ifname = k;
        where = "${siteName}:${nodeName}.interfaces";
      }) (ifaceKeys node);

      fromCont = lib.concatMap (
        cname:
        map (k: {
          ifname = k;
          where = "${siteName}:${nodeName}.${cname}.interfaces";
        }) (ifaceKeys (node.${cname} or { }))
      ) (common.containersOf node);
    in
    top ++ fromCont;

  addOne =
    acc: e:
    if acc.seen ? "${e.ifname}" then
      throw ''
        invariants(node-interface-names-unique-everywhere):

        interface name duplicated within a single node

          interface: ${e.ifname}

        first seen at:
          ${acc.seen.${e.ifname}}

        duplicated at:
          ${e.where}
      ''
    else
      acc
      // {
        seen = acc.seen // {
          "${e.ifname}" = e.where;
        };
      };

in
{
  check =
    { site }:
    let
      siteName = toString (site.siteName or "<unknown-site>");
      nodes = site.nodes or { };

      _ = lib.forEach (builtins.attrNames nodes) (
        nodeName:
        let
          node = nodes.${nodeName};
          entries = mkEntries { inherit siteName nodeName node; };
          st = builtins.foldl' addOne { seen = { }; } entries;
        in
        builtins.deepSeq st true
      );
    in
    true;
}
