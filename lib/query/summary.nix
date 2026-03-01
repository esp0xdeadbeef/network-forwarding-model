# ./lib/query/summary.nix
{ lib, routed }:

let
  viewNode = import ./view-node.nix { inherit lib; };
  wan = import ./wan.nix { inherit lib routed; };
  multiWan = import ./multi-wan.nix { inherit lib routed; };
  routingTable = import ./routing-table.nix { inherit lib routed; };

  # Back-compat: older/newer routed models may use either `domain` or `domains`
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

  nodes = lib.mapAttrs (name: _: viewNode name routed) routed.nodes;

  inherit wan multiWan routingTable;
}
