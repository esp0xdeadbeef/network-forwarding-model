{ lib }:

let
  ip = import ../net/ip-utils.nix { inherit lib; };
  link = import ../topology/link-utils.nix { inherit lib; };

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
      names = builtins.attrNames links;
      hits = lib.filter (
        lname:
        let
          l = links.${lname};
          m = link.membersOf l;
        in
        lib.elem left m && lib.elem right m
      ) names;
    in
    if hits == [ ] then null else lib.head (lib.sort (x: y: x < y) hits);

  neighborsOf =
    { links, node }:
    let
      names = lib.sort (a: b: a < b) (builtins.attrNames links);
      step =
        acc: lname:
        let
          l = links.${lname};
          m = link.membersOf l;
        in
        if lib.elem node m then acc ++ (lib.filter (x: x != node) m) else acc;
    in
    lib.sort (a: b: a < b) (lib.unique (builtins.foldl' step [ ] names));

  shortestPath =
    {
      links,
      src,
      dst,
    }:
    if src == dst then
      [ src ]
    else
      let
        bfs =
          {
            queue,
            visited,
            parent,
          }:
          if queue == [ ] then
            null
          else
            let
              cur = lib.head queue;
              rest = lib.tail queue;
            in
            if cur == dst then
              let
                unwind = n: acc: if n == null then acc else unwind (parent.${n} or null) ([ n ] ++ acc);
              in
              unwind dst [ ]
            else
              let
                ns = neighborsOf {
                  inherit links;
                  node = cur;
                };
                fresh = lib.filter (n: !(visited ? "${n}")) ns;
                visited' = builtins.foldl' (acc: n: acc // { "${n}" = true; }) visited fresh;
                parent' = builtins.foldl' (acc: n: acc // { "${n}" = cur; }) parent fresh;
              in
              bfs {
                queue = rest ++ fresh;
                visited = visited';
                parent = parent';
              };
      in
      bfs {
        queue = [ src ];
        visited = {
          "${src}" = true;
        };
        parent = { };
      };

  nextHop =
    {
      links,
      from,
      to,
      stripMask ? ip.stripMask,
    }:
    let
      lname = findLinkBetween { inherit links from to; };
      l = if lname == null then null else links.${lname};
      epTo = if l == null then { } else link.getEp lname l to;
    in
    {
      linkName = lname;
      via4 = if epTo ? addr4 && epTo.addr4 != null then stripMask epTo.addr4 else null;
      via6 = if epTo ? addr6 && epTo.addr6 != null then stripMask epTo.addr6 else null;
    };
in
{
  inherit
    findLinkBetween
    neighborsOf
    shortestPath
    nextHop
    ;
  inherit (link)
    membersOf
    endpointsOf
    chooseEndpointKey
    getEp
    ;
}
