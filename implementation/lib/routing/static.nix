{ lib, self ? { outPath = ./.; }, ... }:

let
  helpers = import ./static-helpers.nix { inherit lib self; };
  routeContext = import ./route-context.nix { inherit lib self; };
  externalIngressUplinkDefaults = import ./external-ingress-uplink-defaults.nix { inherit lib self; };
  internalRoutes = import ./internal-routes.nix { inherit lib self; };
  defaultRoutes = import ./default-routes.nix { inherit lib self; };
  uplinkLearnedRoutes = import ./uplink-learned-routes.nix { inherit lib self; };

  addInternalRoutes =
    topo: routeGraph: nodeName: node:
    internalRoutes.apply {
      inherit topo nodeName node routeContext routeGraph;
    };


  routeDefaultsForNode =
    topo: routeGraph: nodeName: node:
    defaultRoutes.apply {
      inherit topo nodeName node routeContext routeGraph;
    };

  addExternalIngressUplinkDefaults =
    topo: routeGraph: nodeName: node:
    externalIngressUplinkDefaults.apply {
      inherit topo nodeName node routeContext routeGraph;
    };

  addUplinkLearnedRoutesToSelector =
    topo: routeGraph: nodeName: node:
    uplinkLearnedRoutes.addToSelector {
      inherit topo nodeName node routeContext routeGraph;
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
      graph = import ./graph.nix { inherit lib self; };
      routeGraph = graph.context (topo.links or { });
      remotePrefixFacts = internalRoutes.buildRemotePrefixFacts topo;
      skipInternal = builtins.getEnv "S88_NFM_PROFILE_SKIP_INTERNAL_ROUTES" == "1";
      skipNearest = builtins.getEnv "S88_NFM_PROFILE_SKIP_NEAREST_DEFAULTS" == "1";
      skipLaneDefaults = builtins.getEnv "S88_NFM_PROFILE_SKIP_LANE_DEFAULTS" == "1";
      skipExternalIngress = builtins.getEnv "S88_NFM_PROFILE_SKIP_EXTERNAL_INGRESS_DEFAULTS" == "1";
      skipDirectWan = builtins.getEnv "S88_NFM_PROFILE_SKIP_DIRECT_WAN_DEFAULTS" == "1";
      skipUplinkLearned = builtins.getEnv "S88_NFM_PROFILE_SKIP_UPLINK_LEARNED" == "1";

      nodes1 = lib.mapAttrs (
        n: node:
        let
          withInternalRoutes =
            if skipInternal then
              node
            else
              internalRoutes.apply {
                inherit topo;
                nodeName = n;
                inherit node routeContext remotePrefixFacts routeGraph;
              };

          nearestUplinkDefaults = routeDefaultsForNode topo routeGraph n withInternalRoutes;
          withNearestUplinkDefault =
            if skipNearest then withInternalRoutes else nearestUplinkDefaults.addDefaultTowardNearestUplinkCore;

          policyLaneDefaults = routeDefaultsForNode topo routeGraph n withNearestUplinkDefault;
          withPolicyLaneDefaults =
            if skipLaneDefaults then withNearestUplinkDefault else policyLaneDefaults.addDownstreamSelectorPolicyLaneDefaults;

          policyUpstreamLaneDefaults = routeDefaultsForNode topo routeGraph n withPolicyLaneDefaults;
          withPolicyUpstreamLaneDefaults =
            if skipLaneDefaults then withPolicyLaneDefaults else policyUpstreamLaneDefaults.addPolicyUpstreamSelectorLaneDefaults;

          upstreamCoreLaneDefaults = routeDefaultsForNode topo routeGraph n withPolicyUpstreamLaneDefaults;
          withUpstreamCoreLaneDefaults =
            if skipLaneDefaults then withPolicyUpstreamLaneDefaults else upstreamCoreLaneDefaults.addUpstreamSelectorPolicyLaneCoreDefaults;

          withExternalIngressDefaults =
            if skipExternalIngress then
              withUpstreamCoreLaneDefaults
            else
              addExternalIngressUplinkDefaults topo routeGraph n withUpstreamCoreLaneDefaults;

          directWanDefaults = routeDefaultsForNode topo routeGraph n withExternalIngressDefaults;
        in
        if skipDirectWan then withExternalIngressDefaults else directWanDefaults.addDirectWanDefaults
      ) nodes0;

      topo1 = topo // {
        nodes = nodes1;
      };

      nodes2 =
        if skipUplinkLearned then
          nodes1
        else
          lib.mapAttrs (n: node: addUplinkLearnedRoutesToSelector topo1 routeGraph n node) nodes1;
      nodes3 = lib.mapAttrs (stripOverlayNearestDefaults topo1) nodes2;
    in
    topo1 // { nodes = nodes3; };
}
