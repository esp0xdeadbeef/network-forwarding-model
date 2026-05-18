{ lib, self ? { outPath = ./.; }, ... }:

let
  internalRoutes = import (self.outPath + "/implementation/lib/routing/internal-routes.nix") { inherit lib self; };
  defaultRoutes = import (self.outPath + "/implementation/lib/routing/default-routes.nix") { inherit lib self; };
  externalIngressUplinkDefaults =
    import (self.outPath + "/implementation/lib/routing/external-ingress-uplink-defaults.nix") { inherit lib self; };
  uplinkLearnedRoutes = import (self.outPath + "/implementation/lib/routing/uplink-learned-routes.nix") {
    inherit lib self;
  };

  addExternalIngressUplinkDefaults =
    ctx: nodeName: node:
    externalIngressUplinkDefaults.apply {
      inherit nodeName node;
      inherit (ctx) topo routeContext routeFacts routeGraph;
    };

  defaultsFor = ctx: nodeName: node:
    defaultRoutes.apply {
      inherit nodeName node;
      inherit (ctx) topo routeContext routeFacts routeGraph;
    };
in
{
  apply =
    ctx: n: node:
    let
      withInternalRoutes =
        if ctx.skipInternal then
          node
        else
          internalRoutes.apply {
            nodeName = n;
            inherit node;
            inherit (ctx) topo routeContext routeFacts remotePrefixFacts routeGraph;
          };

      withNearestUplinkDefault =
        if ctx.skipNearest then
          withInternalRoutes
        else
          (defaultsFor ctx n withInternalRoutes).addDefaultTowardNearestUplinkCore;

      withPolicyLaneDefaults =
        if ctx.skipLaneDefaults then
          withNearestUplinkDefault
        else
          (defaultsFor ctx n withNearestUplinkDefault).addDownstreamSelectorPolicyLaneDefaults;

      withPolicyUpstreamLaneDefaults =
        if ctx.skipLaneDefaults then
          withPolicyLaneDefaults
        else
          (defaultsFor ctx n withPolicyLaneDefaults).addPolicyUpstreamSelectorLaneDefaults;

      withUpstreamCoreLaneDefaults =
        if ctx.skipLaneDefaults then
          withPolicyUpstreamLaneDefaults
        else
          (defaultsFor ctx n withPolicyUpstreamLaneDefaults).addUpstreamSelectorPolicyLaneCoreDefaults;

      withExternalIngressDefaults =
        if ctx.skipExternalIngress then
          withUpstreamCoreLaneDefaults
        else
          addExternalIngressUplinkDefaults ctx n withUpstreamCoreLaneDefaults;
    in
    if ctx.skipDirectWan then
      withExternalIngressDefaults
    else
      (defaultsFor ctx n withExternalIngressDefaults).addDirectWanDefaults;

  addUplinkLearnedToSelector =
    ctx: nodeName: node:
    uplinkLearnedRoutes.addToSelector {
      inherit nodeName node;
      inherit (ctx) topo routeContext routeFacts routeGraph;
    };
}
