{ lib, ... }:

{
  hasP2pLinkBetween =
    links: a: b:
    lib.any
      (
        linkName:
        let
          l = links.${linkName};
          members = l.members or [ ];
        in
        (l.kind or null) == "p2p" && lib.elem a members && lib.elem b members
      )
      (builtins.attrNames links);

  p2pLinkNames =
    links: lib.filter (linkName: (links.${linkName}.kind or null) == "p2p") (builtins.attrNames links);
}
