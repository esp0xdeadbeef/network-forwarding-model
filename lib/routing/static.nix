{ lib }:

let
  routeContext = import ./route-context.nix { inherit lib; };
  externalIngressUplinkDefaults = import ./external-ingress-uplink-defaults.nix { inherit lib; };
  internalRoutes = import ./internal-routes.nix { inherit lib; };
  defaultRoutes = import ./default-routes.nix { inherit lib; };
  uplinkLearnedRoutes = import ./uplink-learned-routes.nix { inherit lib; };
  inherit (routeContext)
    laneAccessNodeNameFromLinkName
    laneUplinkNameFromLinkName
    loopbackOwnerNodeForDst
    mkRoute4
    mkRoute6
    nextHopWithPreferredUplinks
    ;


  addInternalRoutes =
    topo: nodeName: node:
    internalRoutes.apply {
      inherit
        topo
        nodeName
        node
        nextHopWithPreferredUplinks
        laneUplinkNameFromLinkName
        loopbackOwnerNodeForDst
        mkRoute4
        mkRoute6
        ;
    };


  routeDefaultsForNode =
    topo: nodeName: node:
    defaultRoutes.apply {
      inherit
        topo
        nodeName
        node
        nextHopWithPreferredUplinks
        laneAccessNodeNameFromLinkName
        mkRoute4
        mkRoute6
        ;
    };

  addExternalIngressUplinkDefaults =
    topo: nodeName: node:
    externalIngressUplinkDefaults.apply {
      inherit
        topo
        nodeName
        node
        nextHopWithPreferredUplinks
        mkRoute4
        mkRoute6
        ;
    };

  addUplinkLearnedRoutesToSelector =
    topo: nodeName: node:
    uplinkLearnedRoutes.addToSelector {
      inherit
        topo
        nodeName
        node
        nextHopWithPreferredUplinks
        mkRoute4
        mkRoute6
        ;
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

          withExternalIngressDefaults = addExternalIngressUplinkDefaults topo n withPolicyUpstreamLaneDefaults;

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
