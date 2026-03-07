{ lib }:

nodeName: topo:

let
  nodeContext = import ./node-context.nix { inherit lib; };

  ctx = nodeContext {
    routed = topo;
    inherit nodeName;
  };

in
{
  node = ctx.node;
  interfaces = ctx.config;
}
