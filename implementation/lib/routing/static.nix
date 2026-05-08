{ lib, self ? { outPath = ./.; }, ... }:

let
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

in
{
  attach =
    topo:
    let
      nodes0 = topo.nodes or { };

      nodes1 = lib.mapAttrs (
        n: node:
        let
          withInternalRoutes = addInternalRoutes topo n node;

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
    in
    topo1 // { nodes = nodes2; };
}
