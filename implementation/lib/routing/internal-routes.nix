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
  apply =
    {
      topo,
      nodeName,
      node,
      nextHopWithPreferredUplinks,
      laneUplinkNameFromLinkName,
      loopbackOwnerNodeForDst,
      mkRoute4,
      mkRoute6,
    }:
    let
      aggregatePrefixesForNode =
        let
          mode = helpers.aggregationMode topo;
          ownSet = helpers.ownConnectedPrefixes topo.nodes.${nodeName};
          remote = lib.filter (e: !(ownSet ? "${toString e.family}|${e.dst}")) (
            (remotePrefixes.ofKind topo nodeName "p2p")
            ++ (remotePrefixes.ofKind topo nodeName "tenant")
            ++ (remotePrefixes.ofKind topo nodeName "overlay")
          );

          resolved = builtins.concatLists (
            map (
              dstEntry:
              remoteResolver.resolve {
                inherit
                  dstEntry
                  laneUplinkNameFromLinkName
                  loopbackOwnerNodeForDst
                  nextHopWithPreferredUplinks
                  nodeName
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
              routes4 = helpers.dedupeRoutes ((acc.${built.linkName}.routes4 or [ ]) ++ built.routes4);
              routes6 = helpers.dedupeRoutes ((acc.${built.linkName}.routes6 or [ ]) ++ built.routes6);
            };
          }
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
