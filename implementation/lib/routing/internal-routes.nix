{ lib, self ? { outPath = ./.; }, ... }:

let
  helpers = import (self.outPath + "/lib/routing/static-helpers.nix") { inherit lib self; };
  remotePrefixes = import (self.outPath + "/implementation/lib/routing/internal-routes/remote-prefixes.nix") {
    inherit lib self;
  };
  remoteResolver = import (self.outPath + "/implementation/lib/routing/internal-routes/resolve-remote-prefix.nix") {
    inherit lib self;
  };
  routeGroups = import (self.outPath + "/implementation/lib/routing/internal-routes/route-groups.nix") {
    inherit lib self;
  };
in
{
  buildRemotePrefixFacts = remotePrefixes.buildFacts;

  apply =
    {
      topo,
      nodeName,
      node,
      routeContext,
      remotePrefixFacts ? remotePrefixes.buildFacts topo,
    }:
    let
      inherit (routeContext) mkRoute4 mkRoute6;

      aggregatePrefixesForNode =
        let
          mode = helpers.aggregationMode topo;
          ownSet = helpers.ownConnectedPrefixes topo.nodes.${nodeName};
          remote = lib.filter (e: !(ownSet ? "${toString e.family}|${e.dst}")) (
            (remotePrefixes.ofKindWithFacts remotePrefixFacts topo nodeName "p2p")
            ++ (remotePrefixes.ofKindWithFacts remotePrefixFacts topo nodeName "tenant")
            ++ (remotePrefixes.ofKindWithFacts remotePrefixFacts topo nodeName "overlay")
          );
          resolved = builtins.concatLists (
            map (
              dstEntry:
              remoteResolver.resolve {
                inherit
                  dstEntry
                  nodeName
                  routeContext
                  topo
                  ;
              }
            ) remote
          );

          perNextHopKey =
            e:
            "${e.linkName}|${toString e.family}|${toString (e.via4 or "")}|${toString (e.via6 or "")}|${e.kind}|${toString (e.overlay or "")}|${toString (e.peerSite or "")}";

          grouped = builtins.foldl' (
            acc: e: acc // { "${perNextHopKey e}" = (acc.${perNextHopKey e} or [ ]) ++ [ e ]; }
          ) { } resolved;
        in
        builtins.mapAttrs
          (_linkName: routes: {
            routes4 = helpers.dedupeRoutes routes.routes4;
            routes6 = helpers.dedupeRoutes routes.routes6;
          })
          (
            builtins.foldl' (
              acc: entries:
              let
                built = routeGroups.build {
                  inherit
                    entries
                    mkRoute4
                    mkRoute6
                    mode
                    topo
                    ;
                };
              in
              acc
              // {
                "${built.linkName}" = {
                  routes4 = (acc.${built.linkName}.routes4 or [ ]) ++ built.routes4;
                  routes6 = (acc.${built.linkName}.routes6 or [ ]) ++ built.routes6;
                };
              }
            ) { } (builtins.attrValues grouped)
          );

      perLink = aggregatePrefixesForNode;
    in
    builtins.foldl' (
      acc: linkName:
      let
        add = perLink.${linkName};
      in
      helpers.addRoutesOnLink acc linkName add.routes4 add.routes6
    ) node (builtins.attrNames perLink);
}
