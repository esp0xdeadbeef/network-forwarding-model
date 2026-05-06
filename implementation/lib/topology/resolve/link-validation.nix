{ lib, self ? { outPath = ./.; }, ... }:

let
  link = import (self.outPath + "/lib/topology/link-utils.nix") { inherit lib self; };

in
{
  validateLinks =
    {
      siteName,
      links,
      nodeNames,
      linkMembersFor,
      assert_,
    }:
    let
      validateLink =
        linkName:
        let
          l = links.${linkName};
          explicitMembers = l.members or [ ];
          endpointKeys = builtins.attrNames (link.endpointsOf l);

          _membersExist = lib.forEach explicitMembers (
            nodeName:
            assert_ (
              builtins.elem nodeName nodeNames
            ) "topology-resolve: link '${linkName}' references unknown member node '${nodeName}'"
          );

          _endpointsExist = lib.forEach endpointKeys (
            epKey:
            let
              _resolved = link.resolveEndpointNodeName {
                inherit linkName;
                link = l;
                inherit epKey nodeNames;
              };
            in
            true
          );

          finalMembers = linkMembersFor linkName l;
          _nonOrphan = assert_ (
            finalMembers != [ ]
          ) "topology-resolve: link '${linkName}' is orphaned (no valid members/endpoints)";

          _p2pShape =
            if (l.kind or null) != "p2p" then
              true
            else
              let
                membersSorted = lib.sort (a: b: a < b) finalMembers;
              in
              builtins.seq
                (assert_ (builtins.length membersSorted == 2) ''
                  topology-resolve: p2p link must resolve to exactly 2 member nodes

                  site: ${siteName}
                  link: ${linkName}
                  members: ${lib.concatStringsSep ", " membersSorted}
                '')
                (
                  assert_ ((builtins.elemAt membersSorted 0) != (builtins.elemAt membersSorted 1)) ''
                    topology-resolve: p2p self-link is not allowed

                    site: ${siteName}
                    link: ${linkName}
                    node: ${builtins.elemAt membersSorted 0}
                  ''
                );
        in
        builtins.deepSeq _membersExist (
          builtins.deepSeq _endpointsExist (builtins.seq _nonOrphan (builtins.seq _p2pShape true))
        );
    in
    builtins.deepSeq (lib.forEach (lib.sort (a: b: a < b) (builtins.attrNames links)) validateLink) true;

  resolvedP2pPairs =
    {
      links,
      linkMembersFor,
    }:
    lib.filter (x: x != null) (
      map (
        linkName:
        let
          l = links.${linkName};
        in
        if (l.kind or null) != "p2p" then
          null
        else
          let
            members = lib.sort (a: b: a < b) (linkMembersFor linkName l);
          in
          {
            inherit linkName members;
            key = "${builtins.elemAt members 0}|${builtins.elemAt members 1}";
          }
      ) (lib.sort (a: b: a < b) (builtins.attrNames links))
    );
}
