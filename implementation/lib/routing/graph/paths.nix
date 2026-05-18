{ lib, self ? { outPath = ./.; }, ... }:

let
  trace = import (self.outPath + "/lib/trace.nix") { };
in
{
  shortestPathWithNeighbors =
    {
      neighbors,
      src,
      dst,
    }:
    trace.emit "graph:shortestPath" (
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
                  ns = neighbors.${cur} or [ ];
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
        }
    );
}
