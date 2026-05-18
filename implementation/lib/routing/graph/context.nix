{ lib, self ? { outPath = ./.; }, ... }:

let
  maps = import ./maps.nix { inherit lib self; };
  paths = import ./paths.nix { inherit lib self; };
  trace = import (self.outPath + "/lib/trace.nix") { };
in
{
  build =
    links:
    opts:
    let
      nodeNames = opts.nodeNames or [ ];
      neighbors = maps.neighborMap links;
      pairs = maps.linkPairMap links;
      graphNodeNames = lib.sort (a: b: a < b) (lib.unique ((builtins.attrNames neighbors) ++ (map toString nodeNames)));
      pathCache = builtins.listToAttrs (
        map (src: {
          name = src;
          value = paths.shortestPathsFromWithNeighbors { inherit neighbors src; };
        }) graphNodeNames
      );
      cachedPath =
        { src, dst }:
        if builtins.hasAttr src pathCache then
          pathCache.${src}.${dst} or null
        else
          trace.emit "graph:fallback:${toString src}->${toString dst}" (
            paths.shortestPathWithNeighbors { inherit neighbors src dst; }
          );
    in
    trace.emit "graph:context:links=${toString (builtins.length (builtins.attrNames links))}" {
      inherit neighbors pairs;
      shortestPath = cachedPath;
      linksBetween = from: to: maps.linksBetween pairs from to;
      findLinkBetween =
        { a ? null, b ? null, from ? null, to ? null }:
        let
          left = if a != null then a else from;
          right = if b != null then b else to;
          hits = maps.linksBetween pairs left right;
        in
        if hits == [ ] then null else builtins.head hits;
    };
}
