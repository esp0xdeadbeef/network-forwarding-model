{ lib, self ? { outPath = ./.; }, ... }:

nodeName: topo:

let
  nodeContext = import ./node-context.nix { inherit lib self; };

  ctx = nodeContext {
    routed = topo;
    inherit nodeName;
  };

in
{
  node = ctx.node;
  interfaces = ctx.config;
}
