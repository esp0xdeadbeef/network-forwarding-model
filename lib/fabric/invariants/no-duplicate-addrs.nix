{ lib }:

let
  common = import ./common.nix { inherit lib; };
  iface = import ./interface-utils.nix { inherit lib; };

  collectExecutionAddrs =
    site:
    let
      siteName = toString (site.siteName or "<unknown-site>");
      nodes = site.nodes or { };
    in
    iface.nonEmptyEntries (
      lib.concatMap (
        nodeName:
        let
          node = nodes.${nodeName};

          nodeIfs = iface.ifaceEntriesFrom {
            whereBase = "${siteName}:nodes.${nodeName}.interfaces";
            ifaces = node.interfaces or { };
            extra = {
              box = "${siteName}:${nodeName}";
            };
          };

          contIfs = lib.concatMap (
            cname:
            let
              c = node.${cname} or { };
            in
            iface.ifaceEntriesFrom {
              whereBase = "${siteName}:nodes.${nodeName}.${cname}.interfaces";
              ifaces = c.interfaces or { };
              extra = {
                box = "${siteName}:${nodeName}.${cname}";
              };
            }
          ) (common.containersOf node);
        in
        nodeIfs ++ contIfs
      ) (builtins.attrNames nodes)
    );

  checkUniqAcrossBoxes =
    entries:
    let
      step =
        acc: e:
        let
          k = "${e.family}:${toString e.ip}";
        in
        if acc.seen ? "${k}" then
          throw ''
            invariants(no-duplicate-addrs):

            duplicate address across execution contexts (boxes)

              address: ${toString e.ip}   (${e.family})

            first seen at:
              ${acc.seen.${k}.where}

            first seen in box:
              ${acc.seen.${k}.box}

            duplicated at:
              ${e.where}

            duplicated in box:
              ${e.box}
          ''
        else
          acc
          // {
            seen = acc.seen // {
              "${k}" = {
                box = e.box;
                where = e.where;
              };
            };
          };

      st = builtins.foldl' step { seen = { }; } entries;
    in

    builtins.deepSeq st true;

in
{
  check =
    { site }:
    let
      entries = collectExecutionAddrs site;
    in
    checkUniqAcrossBoxes entries;
}
