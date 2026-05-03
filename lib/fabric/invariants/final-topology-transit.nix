{ lib }:

let
  common = import ./common.nix { inherit lib; };

  sortedNames = attrs: lib.sort (a: b: a < b) (builtins.attrNames attrs);
in
{
  checkTransit =
    {
      siteName,
      links,
      linkIdToName,
      adjacencies,
    }:
    let
      linkNames = sortedNames links;
      p2pLinkNames = lib.filter (linkName: (links.${linkName}.kind or null) == "p2p") linkNames;

      _adjIdsPresent = lib.imap0 (
        adjacencyIndex: adjacency:
        common.assert_ ((adjacency.id or null) != null) ''
          invariants(final-topology-integrity):

          transit adjacency is missing stable link identity

          site: ${siteName}
          index: ${toString adjacencyIndex}
        ''
      ) adjacencies;

      adjacencyIdToIndex =
        let
          step =
            indexesByAdjacencyId: item:
            let
              adjacencyIndex = item.adjacencyIndex;
              adjacency = item.adjacency;
              id = toString (adjacency.id or "");
            in
            if indexesByAdjacencyId ? "${id}" then
              throw ''
                invariants(final-topology-integrity):

                duplicate transit adjacency identity detected

                site: ${siteName}
                adjacencyId: ${id}

                first index:
                ${toString indexesByAdjacencyId.${id}}

                duplicate index:
                ${toString adjacencyIndex}
              ''
            else
              indexesByAdjacencyId // { "${id}" = adjacencyIndex; };

          indexed = lib.imap0 (
            adjacencyIndex: adjacency: { inherit adjacency adjacencyIndex; }
          ) adjacencies;
        in
        builtins.foldl' step { } indexed;

      _adjIdsKnown = lib.forEach (builtins.attrNames adjacencyIdToIndex) (
        id:
        common.assert_ (linkIdToName ? "${id}") ''
          invariants(final-topology-integrity):

          transit adjacency references unknown link identity

          site: ${siteName}
          adjacencyId: ${id}
        ''
      );

      _adjShape = lib.forEach (builtins.attrNames adjacencyIdToIndex) (
        id:
        let
          adjacency = builtins.elemAt adjacencies adjacencyIdToIndex.${id};
          linkName = linkIdToName.${id};
          expectedMembers = lib.sort (a: b: a < b) (links.${linkName}.members or [ ]);
          gotMembers = lib.sort (
            a: b: a < b
          ) (map (endpoint: toString (endpoint.unit or "")) (adjacency.endpoints or [ ]));
        in
        builtins.seq
          (common.assert_ (builtins.length (adjacency.endpoints or [ ]) == 2) ''
            invariants(final-topology-integrity):

            transit adjacency must have exactly 2 endpoints

            site: ${siteName}
            adjacencyId: ${id}
          '')
          (
            common.assert_ (gotMembers == expectedMembers) ''
              invariants(final-topology-integrity):

              transit adjacency endpoint set does not match realized p2p link

              site: ${siteName}
              adjacencyId: ${id}
              link: ${linkName}
              expectedMembers: ${builtins.toJSON expectedMembers}
              gotMembers: ${builtins.toJSON gotMembers}
            ''
          )
      );

      expectedP2pIds = sortedNames (
        builtins.listToAttrs (
          map (linkName: {
            name = toString (links.${linkName}.id or "");
            value = true;
          }) p2pLinkNames
        )
      );
      gotAdjacencyIds = sortedNames adjacencyIdToIndex;

      _adjComplete = common.assert_ (expectedP2pIds == gotAdjacencyIds) ''
        invariants(final-topology-integrity):

        realized p2p links and emitted transit adjacencies are inconsistent

        site: ${siteName}
        expectedAdjacencyIds: ${builtins.toJSON expectedP2pIds}
        gotAdjacencyIds: ${builtins.toJSON gotAdjacencyIds}
      '';
    in
    builtins.deepSeq _adjIdsPresent (
      builtins.deepSeq adjacencyIdToIndex (
        builtins.deepSeq _adjIdsKnown (builtins.deepSeq _adjShape (builtins.seq _adjComplete true))
      )
    );
}
