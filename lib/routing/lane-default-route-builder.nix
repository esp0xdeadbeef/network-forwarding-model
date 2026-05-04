{ lib }:

let
  graph = import ./graph.nix { inherit lib; };
  helpers = import ./static-helpers.nix { inherit lib; };
in
rec {
  mkDefaultRoutes =
    {
      epTo,
      mkRoute4,
      mkRoute6,
      metric ? null,
      lane ? null,
      reason ? null,
    }:
    let
      via4 = if epTo ? addr4 && epTo.addr4 != null then helpers.stripMask epTo.addr4 else null;
      via6 = if epTo ? addr6 && epTo.addr6 != null then helpers.stripMask epTo.addr6 else null;
    in
    {
      routes4 =
        if via4 == null then
          [ ]
        else
          [
            (mkRoute4 {
              dst = helpers.default4;
              inherit
                lane
                metric
                reason
                via4
                ;
              proto = "default";
              intentKind = "default-reachability";
            })
          ];
      routes6 =
        if via6 == null then
          [ ]
        else
          [
            (mkRoute6 {
              dst = helpers.default6;
              inherit
                lane
                metric
                reason
                via6
                ;
              proto = "default";
              intentKind = "default-reachability";
            })
          ];
    };

  addDefaultsTowardPeer =
    {
      links,
      node,
      linkName,
      peerNodeName,
      mkRoute4,
      mkRoute6,
      metric ? null,
      lane ? null,
      reason ? null,
    }:
    let
      linkObj = links.${linkName};
      routes = mkDefaultRoutes {
        inherit
          lane
          metric
          mkRoute4
          mkRoute6
          reason
          ;
        epTo = graph.getEp linkName linkObj peerNodeName;
      };
    in
    helpers.addRoutesOnLink node linkName routes.routes4 routes.routes6;
}
