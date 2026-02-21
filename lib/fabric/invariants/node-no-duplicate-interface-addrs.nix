{ lib }:

let
  stripMask =
    s:
    let
      parts = lib.splitString "/" (toString s);
    in
    if builtins.length parts == 0 then "" else builtins.elemAt parts 0;

  assert_ = cond: msg: if cond then true else throw msg;

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
      siteName,
      nodeName,
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
            where = "${siteName}:nodes.${nodeName}.${whereBase}.${ifName}.${fam}";
            ifname = ifName;
          };
        in
        lib.flatten [
          (lib.optional (iface ? addr4 && iface.addr4 != null) (mk "addr4" iface.addr4))
          (lib.optional (iface ? addr6 && iface.addr6 != null) (mk "addr6" iface.addr6))
        ]
      ) (builtins.attrNames ifaces);

  checkNode =
    {
      siteName,
      nodeName,
      node,
    }:
    let
      topIfs = node.interfaces or { };
      conts = containersOf node;

      contEntries = lib.concatMap (
        cname:
        let
          c = node.${cname} or { };
          ifs = c.interfaces or { };
        in
        ifaceEntriesFrom {
          inherit siteName nodeName;
          whereBase = "${cname}.interfaces";
          ifaces = ifs;
        }
      ) conts;

      entries =
        (ifaceEntriesFrom {
          inherit siteName nodeName;
          whereBase = "interfaces";
          ifaces = topIfs;
        })
        ++ contEntries;

      entries' = lib.filter (e: (toString e.ip) != "") entries;

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
