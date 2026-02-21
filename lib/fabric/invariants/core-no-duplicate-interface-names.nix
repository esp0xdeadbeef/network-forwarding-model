{ lib }:

let
  assert_ = cond: msg: if cond then true else throw msg;

  isContainerAttr =
    name: v:
    builtins.isAttrs v
    && !(lib.elem name [
      "role"
      "networks"
      "interfaces"
    ]);

  containerNamesOf = node: builtins.attrNames (lib.filterAttrs isContainerAttr node);

  ifaceKeys =
    x:
    if builtins.isAttrs x && x ? interfaces && builtins.isAttrs x.interfaces then
      builtins.attrNames x.interfaces
    else
      [ ];

  addSeen =
    { seen, entries }:
    { where, ifname }:
    if seen ? "${ifname}" then
      throw ''
        invariants(core-no-duplicate-interface-names):

        interface name duplicated on core node

          interface: ${ifname}

        first seen at:
          ${seen.${ifname}}

        duplicated at:
          ${where}
      ''
    else
      {
        seen = seen // {
          "${ifname}" = where;
        };
        entries = entries ++ [ { inherit where ifname; } ];
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
          role = node.role or null;
        in
        if role != "core" then
          true
        else
          let
            containers = containerNamesOf node;

            ownIfs = ifaceKeys node;
            ownEntries = map (k: {
              where = "${siteName}:${nodeName}.interfaces";
              ifname = k;
            }) ownIfs;

            contEntries = lib.concatMap (
              cname:
              let
                ks = ifaceKeys (node.${cname} or { });
              in
              map (k: {
                where = "${siteName}:${nodeName}.${cname}.interfaces";
                ifname = k;
              }) ks
            ) containers;

            all = ownEntries ++ contEntries;

            _scan = builtins.foldl' addSeen {
              seen = { };
              entries = [ ];
            } all;
          in
          builtins.deepSeq _scan true
      );
    in
    true;
}
