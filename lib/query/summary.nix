{ lib, routed }:

let
  viewNode = import ./view-node.nix { inherit lib; };
  wan = import ./wan.nix { inherit lib routed; };
  multiWan = import ./multi-wan.nix { inherit lib routed; };
  routingTable = import ./routing-table.nix { inherit lib routed; };
in
{
  topology = {
    domain = routed.domain;
    nodes = lib.attrNames routed.nodes;
    links = lib.attrNames routed.links;
  };

  nodes = lib.mapAttrs (name: _: viewNode name routed) routed.nodes;

  inherit wan multiWan routingTable;
}
