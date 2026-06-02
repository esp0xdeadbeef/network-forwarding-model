{ lib, self ? { outPath = ./.; }, ... }:

{
  build =
    { helpers
    , nodeNames
    , nodes
    , topo
    ,
    }:
    let
      p2pByOwner = builtins.listToAttrs (
        map
          (owner: {
            name = owner;
            value =
              map
                (x: x // { inherit owner; kind = "p2p"; })
                (builtins.attrValues (helpers.prefixSetFromP2pIfaces nodes.${owner}));
          })
          nodeNames
      );

      p2pEntries = lib.concatMap (owner: p2pByOwner.${owner} or [ ]) nodeNames;

      overlayRouteEntries = lib.concatMap
        (
          overlay:
          let
            owners = overlay.terminateOn or [ ];
            v4s = map (r: {
              family = 4;
              dst = r.dst or null;
              peerSite = r.peerSite or (overlay.peerSite or null);
              overlay = r.overlay or (overlay.overlay or null);
            }) (overlay.routes4 or [ ]);
            v6s = map (r: {
              family = 6;
              dst = r.dst or null;
              peerSite = r.peerSite or (overlay.peerSite or null);
              overlay = r.overlay or (overlay.overlay or null);
            }) (overlay.routes6 or [ ]);
            prefixes = lib.filter (e: e.dst != null) (v4s ++ v6s);
          in
          lib.concatMap
            (
              owner:
              map
                (
                  e:
                  e
                  // {
                    inherit owner;
                    kind = "overlay";
                    overlay = e.overlay or (overlay.overlay or null);
                    peerSite = e.peerSite or (overlay.peerSite or null);
                  }
                )
                prefixes
            )
            owners
        )
        (builtins.attrValues (topo.overlayReachability or { }));

      ownConnectedPrefixSetByNode = builtins.listToAttrs (
        map
          (nodeName: {
            name = nodeName;
            value = helpers.ownConnectedPrefixes nodes.${nodeName};
          })
          nodeNames
      );
    in
    {
      inherit
        ownConnectedPrefixSetByNode
        p2pByOwner
        p2pEntries
        overlayRouteEntries
        ;
      overlayEntries = builtins.attrValues (topo.overlayReachability or { });
    };
}
