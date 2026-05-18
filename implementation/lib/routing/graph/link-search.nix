{ lib, self ? { outPath = ./.; }, ... }:

let
  link = import (self.outPath + "/implementation/lib/topology/link-utils.nix") { inherit lib self; };
in
{
  findLinkBetween =
    {
      links,
      a ? null,
      b ? null,
      from ? null,
      to ? null,
    }:
    let
      left = if a != null then a else from;
      right = if b != null then b else to;
      hits = lib.filter (
        lname:
        let
          members = link.membersOf links.${lname};
        in
        lib.elem left members && lib.elem right members
      ) (builtins.attrNames links);
    in
    if hits == [ ] then null else lib.head (lib.sort (x: y: x < y) hits);
}
