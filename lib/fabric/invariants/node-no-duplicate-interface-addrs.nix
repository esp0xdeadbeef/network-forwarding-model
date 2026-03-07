{ lib }:

let
  common = import ./common.nix { inherit lib; };
  iface = import ./interface-utils.nix { inherit lib; };

  checkNode =
    {
      siteName,
      nodeName,
      node,
    }:
    let
      topIfs = node.interfaces or { };

      contEntries = lib.concatMap (
        cname:
        let
          c = node.${cname} or { };
        in
        iface.ifaceEntriesFrom {
          whereBase = "${siteName}:nodes.${nodeName}.${cname}.interfaces";
          ifaces = c.interfaces or { };
        }
      ) (common.containersOf node);

      entries =
        (iface.ifaceEntriesFrom {
          whereBase = "${siteName}:nodes.${nodeName}.interfaces";
          ifaces = topIfs;
        })
        ++ contEntries;

      entries' = iface.nonEmptyEntries entries;

      step =
        acc: e:
        let
          k = "${e.family}:${toString e.ip}";
        in
        if acc ? "${k}" then
          throw ''
            invariants(node-no-duplicate-interface-addrs):

            duplicate interface address within a single node

              site:  ${siteName}
              node:  ${nodeName}
              addr:  ${toString e.ip} (${e.family})

            first seen at:
              ${acc.${k}}

            duplicated at:
              ${e.where}

            This means the compiler assigned the same host address to multiple
            interface instances under one node (e.g. core containers sharing a p2p IP).
          ''
        else
          acc // { "${k}" = e.where; };

      scanned = builtins.foldl' step { } entries';
    in
    builtins.deepSeq scanned true;

in
{
  check =
    { site }:
    let
      siteName = toString (site.siteName or "<unknown-site>");
      nodes = site.nodes or { };

      done = lib.forEach (builtins.attrNames nodes) (
        nodeName:
        checkNode {
          inherit siteName nodeName;
          node = nodes.${nodeName};
        }
      );
    in
    builtins.deepSeq done true;
}
