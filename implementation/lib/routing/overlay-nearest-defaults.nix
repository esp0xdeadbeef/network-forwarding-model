{ lib, self ? { outPath = ./.; }, ... }:

let
  helpers = import ./static-helpers.nix { inherit lib self; };

  isDefaultRoute =
    route:
    (route.dst or null) == helpers.default4
    || (route.dst or null) == helpers.default6
    || (route.dst or null) == "0000:0000:0000:0000:0000:0000:0000:0000/0";

  addAccess = acc: family: access:
    if access == null then
      acc
    else
      acc // { "${family}" = lib.unique ((acc.${family} or [ ]) ++ [ access ]); };
in
{
  strip =
    topo: _nodeName: node:
    let
      overlayUplinkNameSet = builtins.listToAttrs (
        map
          (name: {
            inherit name;
            value = true;
          })
          (builtins.attrNames (topo.overlayReachability or { }))
      );
      interfaces = node.interfaces or { };
      links = topo.links or { };
      linkFor = ifName: links.${ifName} or { };
      laneFor = ifName: (linkFor ifName).laneMeta or { };
      isOverlayLane =
        ifName:
        let
          lane = laneFor ifName;
          uplink = lane.uplink or null;
        in
        (lane.kind or null) == "access-uplink"
        && uplink != null
        && builtins.hasAttr uplink overlayUplinkNameSet;
      wanPolicyDefaultAccesses =
        builtins.foldl'
          (
            acc: ifName:
              let
                lane = laneFor ifName;
                uplink = lane.uplink or null;
                access = lane.access or null;
                routes = (interfaces.${ifName}.routes or { });
                hasWanPolicyDefault =
                  family:
                  (lane.kind or null) == "access-uplink"
                  && access != null
                  && uplink != null
                  && !(builtins.hasAttr uplink overlayUplinkNameSet)
                  && builtins.any
                    (
                      route:
                      isDefaultRoute route
                      && (route.policyOnly or false) == true
                      && (route.reason or null) == "policy-derived-default"
                    )
                    (routes.${family} or [ ]);
              in
              addAccess (addAccess acc "ipv4" (if hasWanPolicyDefault "ipv4" then access else null)) "ipv6" (
                if hasWanPolicyDefault "ipv6" then access else null
              )
          )
          { ipv4 = [ ]; ipv6 = [ ]; }
          (builtins.attrNames interfaces);
      filterRoutes =
        ifName: family: routes:
        let
          lane = laneFor ifName;
          access = lane.access or null;
        in
        if !(isOverlayLane ifName) || !(builtins.elem access (wanPolicyDefaultAccesses.${family} or [ ])) then
          routes
        else
          lib.filter
            (
              route:
                !(isDefaultRoute route && (route.policyOnly or false) != true && !(builtins.isAttrs (route.lane or null)))
            )
            routes;
    in
    node
    // {
      interfaces = lib.mapAttrs
        (
          ifName: iface:
            let
              routes = iface.routes or { };
            in
            iface // {
              routes = routes // {
                ipv4 = filterRoutes ifName "ipv4" (routes.ipv4 or [ ]);
                ipv6 = filterRoutes ifName "ipv6" (routes.ipv6 or [ ]);
              };
            }
        )
        interfaces;
    };
}
