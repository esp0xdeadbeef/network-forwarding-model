{ lib, ... }:

{
  shortestPath =
    routeGraph:
    {
      src,
      dst,
      forbidden,
    }:
    let
      forbiddenSet = builtins.listToAttrs (
        map (name: {
          name = toString name;
          value = true;
        }) forbidden
      );
      isForbidden = name: forbiddenSet.${toString name} or false;
      unwind =
        parent: n: acc:
        if n == null then acc else unwind parent (parent.${n} or null) ([ n ] ++ acc);
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
            unwind parent dst [ ]
          else
            let
              ns = routeGraph.neighbors.${cur} or [ ];
              allowed = lib.filter (n: n == dst || !(isForbidden n)) ns;
              fresh = lib.filter (n: !(visited ? "${n}")) allowed;
              visited' = builtins.foldl' (acc: n: acc // { "${n}" = true; }) visited fresh;
              parent' = builtins.foldl' (acc: n: acc // { "${n}" = cur; }) parent fresh;
            in
            bfs {
              queue = rest ++ fresh;
              visited = visited';
              parent = parent';
            };
    in
    if src == dst then
      [ src ]
    else if isForbidden src then
      null
    else
      bfs {
        queue = [ src ];
        visited = {
          "${src}" = true;
        };
        parent = { };
      };
}
