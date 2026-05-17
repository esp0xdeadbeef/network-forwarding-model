{ lib, self ? { outPath = ./.; }, ... }:

let
  helpers = import ./static-helpers.nix { inherit lib self; };
  routeContext = import ./route-context.nix { inherit lib self; };
  externalIngressUplinkDefaults = import ./external-ingress-uplink-defaults.nix { inherit lib self; };
  internalRoutes = import ./internal-routes.nix { inherit lib self; };
  defaultRoutes = import ./default-routes.nix { inherit lib self; };
  uplinkLearnedRoutes = import ./uplink-learned-routes.nix { inherit lib self; };

  addInternalRoutes =
    topo: nodeName: node:
    internalRoutes.apply {
      inherit topo nodeName node routeContext;
    };


  routeDefaultsForNode =
    topo: nodeName: node:
    defaultRoutes.apply {
      inherit topo nodeName node routeContext;
    };

  addExternalIngressUplinkDefaults =
    topo: nodeName: node:
    externalIngressUplinkDefaults.apply {
      inherit topo nodeName node routeContext;
    };

  addUplinkLearnedRoutesToSelector =
    topo: nodeName: node:
    uplinkLearnedRoutes.addToSelector {
      inherit topo nodeName node routeContext;
    };

  isDefaultRoute =
    route:
    (route.dst or null) == helpers.default4
    || (route.dst or null) == helpers.default6
    || (route.dst or null) == "0000:0000:0000:0000:0000:0000:0000:0000/0";

  stripOverlayNearestDefaults =
    topo: _nodeName: node:
    let
      overlays = builtins.attrNames (topo.overlayReachability or { });
      interfaces = node.interfaces or { };
      linkFor = ifName: (topo.links or { }).${ifName} or { };
      laneFor = ifName: (linkFor ifName).laneMeta or { };
      isOverlayLane =
        ifName:
        let lane = laneFor ifName;
        in
        (lane.kind or null) == "access-uplink"
        && (lane.uplink or null) != null
        && builtins.elem lane.uplink overlays;
      hasWanPolicyDefault =
        family: access:
        builtins.any (
          ifName:
          let
            lane = laneFor ifName;
            routes = (interfaces.${ifName}.routes or { }).${family} or [ ];
          in
          (lane.kind or null) == "access-uplink"
          && (lane.access or null) == access
          && (lane.uplink or null) != null
          && !(builtins.elem lane.uplink overlays)
          && builtins.any (
            route:
            isDefaultRoute route
            && (route.policyOnly or false) == true
            && (route.reason or null) == "policy-derived-default"
          ) routes
        ) (builtins.attrNames interfaces);
      filterRoutes =
        ifName: family: routes:
        let
          lane = laneFor ifName;
        in
        if !(isOverlayLane ifName) || !(hasWanPolicyDefault family (lane.access or null)) then
          routes
        else
          lib.filter (
            route:
            !(isDefaultRoute route && (route.policyOnly or false) != true && !(builtins.isAttrs (route.lane or null)))
          ) routes;
    in
    node
    // {
      interfaces = lib.mapAttrs (
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
      ) interfaces;
    };

in
{
  attach =
    topo:
    let
      nodes0 = topo.nodes or { };
      remotePrefixFacts = internalRoutes.buildRemotePrefixFacts topo;

      nodes1 = lib.mapAttrs (
        n: node:
        let
          withInternalRoutes =
            internalRoutes.apply {
              inherit topo;
              nodeName = n;
              inherit node routeContext remotePrefixFacts;
            };

          nearestUplinkDefaults = routeDefaultsForNode topo n withInternalRoutes;
          withNearestUplinkDefault = nearestUplinkDefaults.addDefaultTowardNearestUplinkCore;

          policyLaneDefaults = routeDefaultsForNode topo n withNearestUplinkDefault;
          withPolicyLaneDefaults = policyLaneDefaults.addDownstreamSelectorPolicyLaneDefaults;

          policyUpstreamLaneDefaults = routeDefaultsForNode topo n withPolicyLaneDefaults;
          withPolicyUpstreamLaneDefaults = policyUpstreamLaneDefaults.addPolicyUpstreamSelectorLaneDefaults;

          upstreamCoreLaneDefaults = routeDefaultsForNode topo n withPolicyUpstreamLaneDefaults;
          withUpstreamCoreLaneDefaults = upstreamCoreLaneDefaults.addUpstreamSelectorPolicyLaneCoreDefaults;

          withExternalIngressDefaults = addExternalIngressUplinkDefaults topo n withUpstreamCoreLaneDefaults;

          directWanDefaults = routeDefaultsForNode topo n withExternalIngressDefaults;
        in
        directWanDefaults.addDirectWanDefaults
      ) nodes0;

      topo1 = topo // {
        nodes = nodes1;
      };

      nodes2 = lib.mapAttrs (n: node: addUplinkLearnedRoutesToSelector topo1 n node) nodes1;
      nodes3 = lib.mapAttrs (stripOverlayNearestDefaults topo1) nodes2;
    in
    topo1 // { nodes = nodes3; };
}
