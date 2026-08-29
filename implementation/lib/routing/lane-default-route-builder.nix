{
  lib,
  self ? {
    outPath = ./.;
  },
  ...
}:

let
  link = import (self.outPath + "/implementation/lib/topology/link-utils.nix") { inherit lib self; };
  helpers = import ./static-helpers.nix { inherit lib self; };
in
rec {
  mkDefaultRoutes =
    {
      epTo,
      mkRoute4,
      mkRoute6,
      metric ? null,
      lane ? null,
      policyOnly ? false,
      reason ? null,
      relationIds ? null,
      direction ? null,
      returnBehavior ? null,
    }:
    let
      via4 = if epTo ? addr4 && epTo.addr4 != null then helpers.stripMask epTo.addr4 else null;
      via6 = if epTo ? addr6 && epTo.addr6 != null then helpers.stripMask epTo.addr6 else null;

      mkRouteWith =
        route:
        route
        // lib.optionalAttrs (relationIds != null && relationIds != [ ]) { inherit relationIds; }
        // lib.optionalAttrs (direction != null) { inherit direction; }
        // lib.optionalAttrs (returnBehavior != null) { inherit returnBehavior; };
    in
    {
      routes4 =
        if via4 == null then
          [ ]
        else
          [
            (mkRouteWith (mkRoute4 {
              dst = helpers.default4;
              inherit
                lane
                metric
                policyOnly
                reason
                via4
                ;
              proto = "default";
              intentKind = "default-reachability";
            }))
          ];
      routes6 =
        if via6 == null then
          [ ]
        else
          [
            (mkRouteWith (mkRoute6 {
              dst = helpers.default6;
              inherit
                lane
                metric
                policyOnly
                reason
                via6
                ;
              proto = "default";
              intentKind = "default-reachability";
            }))
          ];
    };

  mkMultipathDefaultRoutes =
    args@{ epsTo, multipathAuthority, ... }:
    let
      base = builtins.removeAttrs args [
        "epsTo"
        "multipathAuthority"
      ];
      per = map (epTo: mkDefaultRoutes (base // { inherit epTo; })) epsTo;
      tagRoutes =
        routes:
        map (
          r:
          r
          // {
            multipath = {
              authority = multipathAuthority;
            };
          }
        ) routes;
    in
    {
      routes4 = builtins.concatMap (x: tagRoutes x.routes4) per;
      routes6 = builtins.concatMap (x: tagRoutes x.routes6) per;
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
      policyOnly ? false,
      reason ? null,
      relationIds ? null,
      direction ? null,
      returnBehavior ? null,
    }:
    let
      linkObj = links.${linkName};
      routes = mkDefaultRoutes {
        inherit
          lane
          metric
          policyOnly
          mkRoute4
          mkRoute6
          reason
          relationIds
          direction
          returnBehavior
          ;
        epTo = link.getEp linkName linkObj peerNodeName;
      };
    in
    helpers.addRoutesOnLinkFromMaterializedRoutes node linkName routes.routes4 routes.routes6;
}
