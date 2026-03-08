{ lib }:

let
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
          ownIfs =
            if builtins.isAttrs (node.interfaces or null) then builtins.attrNames node.interfaces else [ ];

          ownEntries = map (k: {
            where = "${siteName}:${nodeName}.interfaces";
            ifname = k;
          }) ownIfs;

          _scan = builtins.foldl' addSeen {
            seen = { };
            entries = [ ];
          } ownEntries;
        in
        if role != "core" then true else builtins.deepSeq _scan true
      );
    in
    true;
}
