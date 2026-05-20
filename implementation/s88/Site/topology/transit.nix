{ lib, self ? { outPath = ./.; }, ... }:

let
  inputOrdering = import (self.outPath + "/implementation/s88/Site/topology/transit/input-ordering.nix") {
    inherit lib self;
  };

  transitAdjacenciesFromLinks = import
    (
      self.outPath + "/implementation/s88/Site/topology/transit/adjacencies.nix"
    )
    { inherit lib self; };

  transitLinkIdForPair = import
    (
      self.outPath + "/implementation/s88/Site/topology/transit/link-id-for-pair.nix"
    )
    { inherit lib self; };

in
{
  normalizeInputOrdering = inputOrdering.normalize;

  inherit
    transitAdjacenciesFromLinks
    transitLinkIdForPair
    ;
}
