{
  lib,
  self ? {
    outPath = ./.;
  },
  ...
}:

let
  helpers = import (self.outPath + "/implementation/lib/routing/static-helpers.nix") {
    inherit lib self;
  };
  defaultRoutePolicy =
    import (self.outPath + "/implementation/lib/routing/default-route-policy.nix")
      {
        inherit lib;
      };
  link = import (self.outPath + "/implementation/lib/topology/link-utils.nix") { inherit lib self; };
  routeCandidates = import (
    self.outPath + "/implementation/lib/routing/internal-routes/route-candidates.nix"
  );
  routeGroups =
    import (self.outPath + "/implementation/lib/routing/internal-routes/route-groups.nix")
      {
        inherit lib self;
      };

  nextHopIdentityKey =
    e:
    let
      routeScope = e.routeScope or { };
    in
    "${e.nodeName}|${e.linkName}|${toString e.family}|${toString (e.via4 or "")}|${toString (e.via6 or "")}|${e.kind}|${toString (e.overlay or "")}|${toString (e.peerSite or "")}|${toString (e.sourceFile or "")}|${
      toString (e.tenant or e.netName or "")
    }|${toString (e.prefixName or "")}|${toString (e.delegatedPrefixLength or "")}|${
      toString (e.perTenantPrefixLength or "")
    }|${toString (e.slot or "")}|${toString (e.prefixPostfix or "")}|${
      toString (routeScope.access or "")
    }|${toString (routeScope.uplink or "")}|${toString (routeScope.serviceName or "")}";

in
{
  inherit nextHopIdentityKey;

  build =
    {
      mkRoute4,
      mkRoute6,
      mode,
      realRouteGraph,
      remoteGroups,
      remotePrefixFacts,
      routeContext,
      routeFacts,
      routeGraph,
      topo,
    }:
    let
      resolveGroupMod = import ./resolve-group-helper.nix {
        inherit
          lib
          helpers
          defaultRoutePolicy
          link
          remotePrefixFacts
          routeCandidates
          routeGraph
          realRouteGraph
          routeFacts
          routeContext
          topo
          ;
      };
      resolveGroup = resolveGroupMod;

      groupValues = keyFn: xs: builtins.groupBy keyFn xs;

      resolveGroupRows =
        group:
        let
          resolvedHops = resolveGroup group;
        in
        lib.concatMap (resolvedHop: map (entry: entry // resolvedHop) group.entries) resolvedHops;

      resolvedRows = lib.concatMap (key: resolveGroupRows remoteGroups.${key}) (
        builtins.attrNames remoteGroups
      );

      nextHopGroups = groupValues nextHopIdentityKey resolvedRows;

      buildRouteRow =
        rows:
        let
          sample = builtins.head rows;
          routeScope = sample.routeScope or { };
          built = routeGroups.build {
            inherit
              mkRoute4
              mkRoute6
              mode
              topo
              ;
            entries = rows;
            linkName = sample.linkName;
            via4 = sample.via4;
            via6 = sample.via6;
          };
        in
        {
          inherit (sample) nodeName;
          inherit (built) linkName routes4 routes6;
          equivalenceKey = {
            sourceNode = sample.nodeName;
            destinationOwner = sample.destinationOwner or null;
            routeKind = sample.kind;
            overlay = sample.overlay or null;
            uplink = routeScope.uplink or null;
            access = routeScope.access or null;
            serviceName = routeScope.serviceName or null;
            hopNode = sample.hopNode or null;
            linkName = sample.linkName;
            family = sample.family;
            via4 = sample.via4 or null;
            via6 = sample.via6 or null;
            sourceFile = sample.sourceFile or null;
            tenant = sample.tenant or sample.netName or null;
            prefixName = sample.prefixName or null;
            delegatedPrefixLength = sample.delegatedPrefixLength or null;
            perTenantPrefixLength = sample.perTenantPrefixLength or null;
            slot = sample.slot or null;
            prefixPostfix = sample.prefixPostfix or null;
            routeIntentClass =
              if sample.kind == "runtime-routed-prefix" then
                "runtime-routed-prefix-return"
              else if sample.kind == "routed-public-ipv4" then
                "routed-public-ipv4-return"
              else if sample.kind == "overlay" then
                "overlay-reachability"
              else
                "internal-reachability";
            routeAtomIds = map (entry: (entry.routeAtom or { }).id or null) rows;
            aggregationClass = sample.aggregationClass or null;
            exceptionClass = sample.exceptionClass or null;
          };
          diagnostics = built.diagnostics;
        };
    in
    map (key: buildRouteRow nextHopGroups.${key}) (builtins.attrNames nextHopGroups);
}
