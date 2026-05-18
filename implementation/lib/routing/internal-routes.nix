{ lib, self ? { outPath = ./.; }, ... }:

let
  graph = import (self.outPath + "/lib/routing/graph.nix") { inherit lib self; };
  helpers = import (self.outPath + "/lib/routing/static-helpers.nix") { inherit lib self; };
  trace = import (self.outPath + "/lib/trace.nix") { };
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
      routeFacts ? routeContext.buildFacts topo,
      remotePrefixFacts ? remotePrefixes.buildFacts topo,
      routeGraph ? graph.context (topo.links or { }),
    }:
    let
      inherit (routeContext) mkRoute4 mkRoute6;

      aggregatePrefixesForNode =
        let
          mode = helpers.aggregationMode topo;
          ownSet = helpers.ownConnectedPrefixes topo.nodes.${nodeName};
          p2pRemote = remotePrefixes.ofKindWithFacts remotePrefixFacts topo nodeName "p2p";
          tenantRemote = remotePrefixes.ofKindWithFacts remotePrefixFacts topo nodeName "tenant";
          overlayRemote = remotePrefixes.ofKindWithFacts remotePrefixFacts topo nodeName "overlay";
          includeP2p = builtins.getEnv "S88_NFM_PROFILE_SKIP_INTERNAL_P2P" != "1";
          includeTenant = builtins.getEnv "S88_NFM_PROFILE_SKIP_INTERNAL_TENANT" != "1";
          includeOverlay = builtins.getEnv "S88_NFM_PROFILE_SKIP_INTERNAL_OVERLAY" != "1";
          remote0 = trace.emit
            "routing:internal:${nodeName}:remote:p2p=${toString (builtins.length p2pRemote)}:tenant=${toString (builtins.length tenantRemote)}:overlay=${toString (builtins.length overlayRemote)}"
            ((if includeP2p then p2pRemote else [ ])
              ++ (if includeTenant then tenantRemote else [ ])
              ++ (if includeOverlay then overlayRemote else [ ]));
          remote = lib.filter (e: !(ownSet ? "${toString e.family}|${e.dst}")) remote0;
          _remoteCount = trace.emit "routing:internal:${nodeName}:remote-filtered=${toString (builtins.length remote)}" true;
          resolutionKey =
            e:
            "${toString (e.owner or "")}|${toString (e.kind or "")}|${toString (e.overlay or "")}|${toString (e.peerSite or "")}";
          remoteGroups = builtins.groupBy resolutionKey remote;
          resolveGroup =
            entries:
            let
              sample = builtins.head entries;
              resolvedSample =
                remoteResolver.resolve {
                  dstEntry = sample;
                  inherit
                    nodeName
                    routeFacts
                    routeContext
                    topo
                    ;
                  inherit routeGraph;
                };
            in
            lib.concatMap (
              resolvedHop:
              map (
                entry:
                entry
                // {
                  hopNode = resolvedHop.hopNode;
                  linkName = resolvedHop.linkName;
                  via4 = resolvedHop.via4;
                  via6 = resolvedHop.via6;
                }
              ) entries
            ) resolvedSample;
          resolved = trace.emit "routing:internal:${nodeName}:resolving:groups=${toString (builtins.length (builtins.attrNames remoteGroups))}" (
            lib.concatMap (key: resolveGroup remoteGroups.${key}) (builtins.attrNames remoteGroups)
          );
          _resolvedCount = trace.emit "routing:internal:${nodeName}:resolved=${toString (builtins.length resolved)}" true;

          perNextHopKey =
            e:
            "${e.linkName}|${toString e.family}|${toString (e.via4 or "")}|${toString (e.via6 or "")}|${e.kind}|${toString (e.overlay or "")}|${toString (e.peerSite or "")}";

          grouped = builtins.groupBy perNextHopKey resolved;
        in
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
          trace.emit "routing:internal:${nodeName}:group:${built.linkName}:entries=${toString (builtins.length entries)}" (
            acc
            // {
              "${built.linkName}" = {
                routes4 = (acc.${built.linkName}.routes4 or [ ]) ++ built.routes4;
                routes6 = (acc.${built.linkName}.routes6 or [ ]) ++ built.routes6;
              };
            }
          )
        ) { } (builtins.attrValues grouped);

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
