{ lib }:

let
  common = import ./common.nix { inherit lib; };

  entriesForNode =
    {
      siteName,
      nodeName,
      node,
    }:
    let
      ownEntries = map (ifName: {
        inherit ifName;
        where = "${siteName}:nodes.${nodeName}.interfaces";
      }) (builtins.attrNames (node.interfaces or { }));

      containerEntries = lib.concatMap (
        cname:
        let
          c = node.${cname} or { };
        in
        map (ifName: {
          inherit ifName;
          where = "${siteName}:nodes.${nodeName}.${cname}.interfaces";
        }) (builtins.attrNames (c.interfaces or { }))
      ) (common.containersOf node);
    in
    ownEntries ++ containerEntries;

  checkUnique =
    entries:
    let
      step =
        seen: e:
        if seen ? "${e.ifName}" then
          throw ''
            invariants(core-containers-unique-interfaces):

            interface name duplicated across core execution contexts

            interface: ${e.ifName}

            first seen at:
            ${seen.${e.ifName}}

            duplicated at:
            ${e.where}
          ''
        else
          seen // { "${e.ifName}" = e.where; };
    in
    builtins.foldl' step { } entries;

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
        in
        if (node.role or null) != "core" then
          true
        else
          builtins.deepSeq (checkUnique (entriesForNode {
            inherit siteName nodeName node;
          })) true
      );
    in
    builtins.deepSeq _ true;
}
