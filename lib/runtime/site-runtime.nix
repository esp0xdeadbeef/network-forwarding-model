{ lib }:

routed: {
  routed = routed;

  query = {
    all-nodes = builtins.attrNames routed.nodes;

    view-node = nodeName: (import ../query/view-node.nix { inherit lib; }) nodeName routed;

    node-context =
      args: (import ../query/node-context.nix { inherit lib; }) ({ inherit routed; } // args);

    wan = import ../query/wan.nix { inherit lib routed; };
    multi-wan = import ../query/multi-wan.nix { inherit lib routed; };
    routing-table = import ../query/routing-table.nix { inherit lib routed; };
  };
}
