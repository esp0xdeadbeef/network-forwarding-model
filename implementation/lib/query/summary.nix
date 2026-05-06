# ./lib/query/summary.nix
{ lib, routed }:

let
  wan = import ./wan.nix { inherit lib routed; };
  multiWan = import ./multi-wan.nix { inherit lib routed; };

  topoDomain =
    if routed ? domain then routed.domain
    else if routed ? domains then routed.domains
    else null;

in
{
  topology = {
    domain = topoDomain;
    nodes = lib.attrNames routed.nodes;
    links = lib.attrNames routed.links;
  };

  inherit wan multiWan;
}
