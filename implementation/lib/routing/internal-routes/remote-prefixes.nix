{ lib, self ? { outPath = ./.; }, ... }:

let
  helpers = import (self.outPath + "/lib/routing/static-helpers.nix") { inherit lib self; };

in
{
  ofKind =
    topo: nodeName: kind:
    let
      tenantOwnerEntries =
        if kind == "tenant" then builtins.attrValues (topo.tenantPrefixOwners or { }) else [ ];

      overlayEntries =
        if kind == "overlay" then builtins.attrValues (topo.overlayReachability or { }) else [ ];

      perTenantOwner =
        entry:
        if entry.owner == nodeName then
          [ ]
        else
          [
            {
              family = entry.family;
              dst = entry.dst;
              owner = entry.owner;
              kind = "tenant";
            }
          ];

      perOverlayOwner =
        overlay:
        let
          owners = overlay.terminateOn or [ ];
          v4s = map (r: { family = 4; dst = r.dst or null; }) (overlay.routes4 or [ ]);
          v6s = map (r: { family = 6; dst = r.dst or null; }) (overlay.routes6 or [ ]);
          prefixes = lib.filter (e: e.dst != null) (v4s ++ v6s);
        in
        lib.concatMap (
          owner:
          if owner == nodeName then
            [ ]
          else
            map (
              e:
              e
              // {
                owner = owner;
                kind = "overlay";
                overlay = overlay.overlay or null;
                peerSite = overlay.peerSite or null;
              }
            ) prefixes
        ) owners;

      perNode =
        other:
        if other == nodeName then
          [ ]
        else
          map (
            x:
            x
            // {
              owner = other;
              kind = "p2p";
            }
          ) (builtins.attrValues (helpers.prefixSetFromP2pIfaces topo.nodes.${other}));
    in
    if kind == "tenant" then
      lib.concatMap perTenantOwner tenantOwnerEntries
    else if kind == "overlay" then
      lib.concatMap perOverlayOwner overlayEntries
    else
      lib.concatMap perNode (helpers.allNodeNames topo);
}
