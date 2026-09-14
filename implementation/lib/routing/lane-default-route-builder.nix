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

  # `epsTo4`/`epsTo6` carry the per-family member sets (FS-315, SMS-010). A
  # route selection key carries one address family, so the IPv4 and IPv6 member
  # sets may differ: an egress that defaults only in one family belongs only to
  # that family's group. `epsTo` remains the single-set form for callers whose
  # members serve both families.
  mkMultipathDefaultRoutes =
    args@{
      epsTo ? null,
      epsTo4 ? null,
      epsTo6 ? null,
      multipathAuthority,
      ...
    }:
    let
      base = builtins.removeAttrs args [
        "epsTo"
        "epsTo4"
        "epsTo6"
        "multipathAuthority"
      ];
      shared = if epsTo == null then [ ] else epsTo;
      members4 = if epsTo4 == null then shared else epsTo4;
      members6 = if epsTo6 == null then shared else epsTo6;
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
      perRoutes =
        f: members: builtins.concatMap (epTo: (mkDefaultRoutes (base // { inherit epTo; })).${f}) members;
    in
    {
      routes4 = tagRoutes (perRoutes "routes4" members4);
      routes6 = tagRoutes (perRoutes "routes6" members6);
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
