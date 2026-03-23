{ lib }:

let
  common = import ./common.nix { inherit lib; };

  sortedNames = attrs: lib.sort (a: b: a < b) (builtins.attrNames attrs);

  isLogicalInterface =
    iface:
    (iface.logical or false)
    || (iface.type or null) == "logical"
    || (iface.carrier or null) == "logical"
    || (iface.link or null) == null;

in
{
  check =
    { site }:
    let
      siteName = toString (site.siteName or "<unknown-site>");
      nodes = site.nodes or { };
      links = site.links or { };
      transit = site.transit or { };
      adjacencies = if builtins.isList (transit.adjacencies or null) then transit.adjacencies else [ ];

      nodeNames = sortedNames nodes;
      linkNames = sortedNames links;
      p2pLinkNames = lib.filter (linkName: (links.${linkName}.kind or null) == "p2p") linkNames;

      _linkIdsPresent = lib.forEach linkNames (
        linkName:
        common.assert_ ((links.${linkName}.id or null) != null) ''
          invariants(final-topology-integrity):

          link is missing stable identity

          site: ${siteName}
          link: ${linkName}
        ''
      );

      linkIdToName =
        let
          step =
            acc: linkName:
            let
              id = toString (links.${linkName}.id or "");
            in
            if acc ? "${id}" then
              throw ''
                invariants(final-topology-integrity):

                duplicate link identity detected

                site: ${siteName}
                linkId: ${id}

                first link:
                ${acc.${id}}

                duplicate link:
                ${linkName}
              ''
            else
              acc // { "${id}" = linkName; };
        in
        builtins.foldl' step { } linkNames;

      _linksOk = lib.forEach linkNames (
        linkName:
        let
          link = links.${linkName};
          members = link.members or [ ];
          endpoints = link.endpoints or { };
          epNodeNames = sortedNames endpoints;
        in
        builtins.seq
          (common.assert_ (members != [ ] || epNodeNames != [ ]) ''
            invariants(final-topology-integrity):

            link has no members/endpoints

            site: ${siteName}
            link: ${linkName}
          '')
          (
            builtins.deepSeq
              (lib.forEach members (
                nodeName:
                builtins.seq
                  (common.assert_ (nodes ? "${nodeName}") ''
                    invariants(final-topology-integrity):

                    link references unknown member node

                    site: ${siteName}
                    link: ${linkName}
                    node: ${nodeName}
                  '')
                  (
                    common.assert_ (nodes.${nodeName}.interfaces or { } ? "${linkName}") ''
                      invariants(final-topology-integrity):

                      link member is missing reverse interface

                      site: ${siteName}
                      link: ${linkName}
                      node: ${nodeName}
                    ''
                  )
              ))
              (
                builtins.deepSeq (lib.forEach epNodeNames (
                  nodeName:
                  let
                    ep = endpoints.${nodeName};
                  in
                  builtins.seq
                    (common.assert_ (nodes ? "${nodeName}") ''
                      invariants(final-topology-integrity):

                      link endpoint references unknown node

                      site: ${siteName}
                      link: ${linkName}
                      endpointNode: ${nodeName}
                    '')
                    (
                      builtins.seq
                        (common.assert_ ((ep.node or nodeName) == nodeName) ''
                          invariants(final-topology-integrity):

                          link endpoint node field mismatches endpoint key

                          site: ${siteName}
                          link: ${linkName}
                          endpointKey: ${nodeName}
                          endpoint.node: ${toString (ep.node or "<missing>")}
                        '')
                        (
                          common.assert_ ((ep.interface or linkName) == linkName) ''
                            invariants(final-topology-integrity):

                            link endpoint interface field mismatches link name

                            site: ${siteName}
                            link: ${linkName}
                            endpointNode: ${nodeName}
                            endpoint.interface: ${toString (ep.interface or "<missing>")}
                          ''
                        )
                    )
                )) true
              )
          )
      );

      _nodesOk = lib.forEach nodeNames (
        nodeName:
        let
          node = nodes.${nodeName};
          ifs = node.interfaces or { };
          ifNames = sortedNames ifs;
        in
        lib.forEach ifNames (
          ifName:
          let
            iface = ifs.${ifName};
          in
          if isLogicalInterface iface then
            true
          else
            builtins.seq
              (common.assert_ (links ? "${ifName}") ''
                invariants(final-topology-integrity):

                node interface references unknown link

                site: ${siteName}
                node: ${nodeName}
                interface: ${ifName}
              '')
              (
                let
                  link = links.${ifName};
                  members = link.members or [ ];
                  endpoints = link.endpoints or { };
                in
                common.assert_ ((lib.elem nodeName members) || (endpoints ? "${nodeName}")) ''
                  invariants(final-topology-integrity):

                  node interface is orphaned from link membership

                  site: ${siteName}
                  node: ${nodeName}
                  interface: ${ifName}
                ''
              )
        )
      );

      _adjIdsPresent = lib.imap0 (
        idx: adj:
        common.assert_ ((adj.id or null) != null) ''
          invariants(final-topology-integrity):

          transit adjacency is missing stable link identity

          site: ${siteName}
          index: ${toString idx}
        ''
      ) adjacencies;

      adjacencyIdToIndex =
        let
          step =
            acc: item:
            let
              idx = item.idx;
              adj = item.adj;
              id = toString (adj.id or "");
            in
            if acc ? "${id}" then
              throw ''
                invariants(final-topology-integrity):

                duplicate transit adjacency identity detected

                site: ${siteName}
                adjacencyId: ${id}

                first index:
                ${toString acc.${id}}

                duplicate index:
                ${toString idx}
              ''
            else
              acc // { "${id}" = idx; };

          indexed = lib.imap0 (idx: adj: { inherit idx adj; }) adjacencies;
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
          adj = builtins.elemAt adjacencies adjacencyIdToIndex.${id};
          linkName = linkIdToName.${id};
          expectedMembers = lib.sort (a: b: a < b) (links.${linkName}.members or [ ]);
          gotMembers = lib.sort (a: b: a < b) (map (ep: toString (ep.unit or "")) (adj.endpoints or [ ]));
        in
        builtins.seq
          (common.assert_ (builtins.length (adj.endpoints or [ ]) == 2) ''
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
    builtins.deepSeq _linkIdsPresent (
      builtins.deepSeq linkIdToName (
        builtins.deepSeq _linksOk (
          builtins.deepSeq _nodesOk (
            builtins.deepSeq _adjIdsPresent (
              builtins.deepSeq adjacencyIdToIndex (
                builtins.deepSeq _adjIdsKnown (builtins.deepSeq _adjShape (builtins.seq _adjComplete true))
              )
            )
          )
        )
      )
    );
}
