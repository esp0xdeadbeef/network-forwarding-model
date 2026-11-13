{ lib, self ? { outPath = ./.; }, ... }:

let
  link = import (self.outPath + "/implementation/lib/topology/link-utils.nix") { inherit lib self; };
  laneOwnership = import ./lane-ownership.nix { inherit lib; };
  inherit (laneOwnership) laneAddressKey;
in
{
  build =
    { helpers
    , nodeNames
    , nodes
    , topo
    ,
    }:
    let
      links = topo.links or { };
      laneKey = entry: laneAddressKey entry.family entry.dst;

      # FS-260 / FS-260-HDS-010-SDS-010-SMS-050: a point-to-point lane address
      # is directly connected state. The link that carries it is the authority
      # for who may hold a route to it: the members of that link, and nobody
      # else. The link is derived from the topology endpoint that carries the
      # lane, not from the owning node's prefix set, which knows the address
      # but not the wire it lives on.
      laneLinkByDst = builtins.foldl' (
        acc: linkName:
        let
          linkObj = links.${linkName};
          members = link.membersOf linkObj;
          endpoints = linkObj.endpoints or { };
          # The addresses that actually terminate on this link, taken from the
          # link endpoint that names them. Reading a member's whole interface
          # set instead would claim every lane that member owns for whichever
          # link happened to be visited first.
          endpointAddresses = builtins.foldl' (
            inner: endpointKey:
            let
              endpoint = endpoints.${endpointKey};
            in
            inner
            ++ lib.optional (endpoint.addr4 or null != null) {
              family = 4;
              dst = endpoint.addr4;
            }
            ++ lib.optional (endpoint.addr6 or null != null) {
              family = 6;
              dst = endpoint.addr6;
            }
          ) [ ] (builtins.attrNames endpoints);
        in
        builtins.foldl' (
          acc2: entry:
          let
            key = laneKey entry;
          in
          # A lane belongs to exactly one link. When two endpoints claim the same
          # lane address the topology itself is inconsistent; keep the first
          # claim so the inconsistency stays visible instead of swapping the
          # owner silently from one evaluation to the next.
          if acc2 ? ${key} then
            acc2
          else
            acc2
            // {
              ${key} = {
                laneLinkName = linkName;
                laneLinkMembers = members;
              };
            }
        ) acc endpointAddresses
      ) { } (builtins.attrNames links);

      p2pByOwner = builtins.listToAttrs (
        map
          (owner: {
            name = owner;
            value =
              map
                (x: x // { inherit owner; kind = "p2p"; } // (laneLinkByDst.${laneKey x} or { }))
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
