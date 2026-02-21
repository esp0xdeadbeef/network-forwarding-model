{ lib }:

let
  stripMask =
    s:
    let
      parts = lib.splitString "/" (toString s);
    in
    if builtins.length parts == 0 then "" else builtins.elemAt parts 0;

  isContainerAttr =
    name: v:
    builtins.isAttrs v
    && !(lib.elem name [
      "role"
      "networks"
      "interfaces"
    ]);

  containersOf = node: builtins.attrNames (lib.filterAttrs isContainerAttr node);

  ifaceEntriesFrom =
    {
      box,
      whereBase,
      ifaces,
    }:
    if !(builtins.isAttrs ifaces) then
      [ ]
    else
      lib.concatMap (
        ifName:
        let
          iface = ifaces.${ifName};

          mk = fam: addr: {
            family = fam;
            ip = stripMask addr;
            inherit box;
            where = "${whereBase}.${ifName}.${fam}";
          };
        in
        lib.flatten [
          (lib.optional (iface ? addr4 && iface.addr4 != null) (mk "addr4" iface.addr4))
          (lib.optional (iface ? addr6 && iface.addr6 != null) (mk "addr6" iface.addr6))
        ]
      ) (builtins.attrNames ifaces);

  collectExecutionAddrs =
    site:
    let
      siteName = toString (site.siteName or "<unknown-site>");
      nodes = site.nodes or { };
    in
    lib.filter (e: (toString e.ip) != "") (
      lib.concatMap (
        nodeName:
        let
          node = nodes.${nodeName};
          conts = containersOf node;

          nodeIfs = ifaceEntriesFrom {
            box = "${siteName}:${nodeName}";
            whereBase = "${siteName}:nodes.${nodeName}.interfaces";
            ifaces = node.interfaces or { };
          };

          contIfs = lib.concatMap (
            cname:
            let
              c = node.${cname} or { };
            in
            ifaceEntriesFrom {
              box = "${siteName}:${nodeName}.${cname}";
              whereBase = "${siteName}:nodes.${nodeName}.${cname}.interfaces";
              ifaces = c.interfaces or { };
            }
          ) conts;
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
