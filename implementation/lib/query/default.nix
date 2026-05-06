{ lib, self ? { outPath = ./.; }, ... }:

{
  sanitize = import ./sanitize.nix { inherit lib self; };

  viewNode = import ./view-node.nix { inherit lib self; };

  wanView = routed: import ./wan.nix { inherit lib routed; };

  multiWanView = routed: import ./multi-wan.nix { inherit lib routed; };

  nodeContext = import ./node-context.nix { inherit lib self; };

  routingTable = routed: import ./routing-table.nix { inherit lib routed; };

  routesPerNode = topo: import ./routes-per-node.nix { inherit lib topo; };

  summary = routed: import ./summary.nix { inherit lib routed; };
}
