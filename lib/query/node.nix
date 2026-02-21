{ lib, routed }:

let
  viewNode = import ./view-node.nix { inherit lib; };
in
nodeName: viewNode nodeName routed
