{ lib, self ? { outPath = ./.; }, ... }:

let
  maps = import ./maps.nix { inherit lib self; };
  paths = import ./paths.nix { inherit lib self; };
  trace = import (self.outPath + "/lib/trace.nix") { };
in
{
  build =
    links:
    let
      neighbors = maps.neighborMap links;
      pairs = maps.linkPairMap links;
      nodeNames = lib.sort (a: b: a < b) (builtins.attrNames neighbors);
      pathCache = builtins.listToAttrs (
        map (src: {
          name = src;
          value = builtins.listToAttrs (
            map (dst: {
              name = dst;
              value = paths.shortestPathWithNeighbors { inherit neighbors src dst; };
            }) nodeNames
          );
        }) nodeNames
      );
      cachedPath =
        { src, dst }:
        if builtins.hasAttr src pathCache && builtins.hasAttr dst pathCache.${src} then
          pathCache.${src}.${dst}
        else
          paths.shortestPathWithNeighbors { inherit neighbors src dst; };
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
