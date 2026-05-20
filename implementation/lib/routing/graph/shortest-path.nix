{ lib, self ? { outPath = ./.; }, ... }:

let
  maps = import ./maps.nix { inherit lib self; };
  paths = import ./paths.nix { inherit lib self; };
in
{
  withLinks =
    { links
    , src
    , dst
    ,
    }:
    paths.shortestPathWithNeighbors {
      neighbors = maps.neighborMap links;
      inherit src dst;
    };

  inherit (paths) shortestPathWithNeighbors;
}
