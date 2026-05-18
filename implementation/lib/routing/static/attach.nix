{ lib, self ? { outPath = ./.; }, ... }:

let
  context = import (self.outPath + "/implementation/lib/routing/static/context.nix") { inherit lib self; };
  nodeRoutes = import (self.outPath + "/implementation/lib/routing/static/node-routes.nix") { inherit lib self; };
  overlayNearestDefaults = import (self.outPath + "/implementation/lib/routing/overlay-nearest-defaults.nix") {
    inherit lib self;
  };
in
{
  attach =
    topo:
    let
      nodes0 = topo.nodes or { };
      ctx0 = context.build topo;
      nodes1 = lib.mapAttrs (nodeRoutes.apply ctx0) nodes0;

      topo1 = topo // {
        nodes = nodes1;
      };
      ctx1 = ctx0 // { topo = topo1; };

      nodes2 =
        if ctx0.skipUplinkLearned then
          nodes1
        else
          lib.mapAttrs (nodeRoutes.addUplinkLearnedToSelector ctx1) nodes1;
      nodes3 = lib.mapAttrs (overlayNearestDefaults.strip topo1) nodes2;
    in
    topo1 // { nodes = nodes3; };
}
