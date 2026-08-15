{
  lib,
  self ? {
    outPath = ./.;
  },
  ...
}:

let
  helpers = import (self.outPath + "/implementation/lib/topology/resolve-helpers.nix") {
    inherit lib self;
  };
  link = import (self.outPath + "/implementation/lib/topology/link-utils.nix") { inherit lib self; };

in
{
  forNode =
    {
      nodeName,
      links,
      nodes,
      linkMembersFor,
      mkLinkIface,
      overlaysForNode,
      overlayReachability,
      assert_,
    }:
    let
      linkNamesForNode =
        let
          linkNamesSorted = lib.sort (a: b: a < b) (lib.attrNames links);
        in
        lib.filter (
          lname:
          let
            l = links.${lname};
          in
          (lib.elem nodeName (linkMembersFor lname l))
          || ((link.chooseEndpointKey lname l nodeName (builtins.attrNames nodes)) != null)
        ) linkNamesSorted;

      linkInterfaces = lib.listToAttrs (
        map (lname: {
          name = lname;
          value = mkLinkIface lname links.${lname} nodeName;
        }) linkNamesForNode
      );

      node = nodes.${nodeName} or { };
      nodeRole = node.role or null;
      nets = helpers.networksOf node;
      logicalInterfaces = lib.listToAttrs (
        map (
          netName:
          let
            ifName = helpers.logicalInterfaceNameFor netName;
          in
          {
            name = ifName;
            value = helpers.mkLogicalIface {
              inherit
                nodeName
                nodeRole
                ifName
                netName
                ;
              net = nets.${netName};
            };
          }
        ) (lib.sort (a: b: a < b) (builtins.attrNames nets))
      );

      overlayInterfaces = lib.listToAttrs (
        map (
          overlay:
          let
            ifName = helpers.overlayInterfaceNameFor overlay.name;
          in
          {
            name = ifName;
            value = helpers.mkOverlayIface {
              inherit
                nodeName
                ifName
                overlay
                node
                ;
              overlayName = overlay.name;
              reachability = overlayReachability.${overlay.name} or null;
            };
          }
        ) (lib.sort (a: b: a.name < b.name) (overlaysForNode nodeName))
      );

      logicalClashes = lib.filter (n: linkInterfaces ? "${n}") (builtins.attrNames logicalInterfaces);
      overlayClashes = lib.filter (n: linkInterfaces ? "${n}" || logicalInterfaces ? "${n}") (
        builtins.attrNames overlayInterfaces
      );

      _noLogicalIfaceClashes =
        assert_ (logicalClashes == [ ])
          "topology-resolve: logical tenant interface(s) collide with link-backed interface(s) on node '${nodeName}': ${lib.concatStringsSep ", " logicalClashes}";

      _noOverlayIfaceClashes =
        assert_ (overlayClashes == [ ])
          "topology-resolve: overlay interface(s) collide with existing interface(s) on node '${nodeName}': ${lib.concatStringsSep ", " overlayClashes}";
    in
    builtins.seq _noLogicalIfaceClashes (
      builtins.seq _noOverlayIfaceClashes (linkInterfaces // logicalInterfaces // overlayInterfaces)
    );
}
