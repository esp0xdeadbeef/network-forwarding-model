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
  checkLinks =
    {
      siteName,
      nodes,
      links,
    }:
    let
      linkNames = sortedNames links;
      nodeNames = sortedNames nodes;

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
            identitiesByLinkId: linkName:
            let
              id = toString (links.${linkName}.id or "");
            in
            if identitiesByLinkId ? "${id}" then
              throw ''
                invariants(final-topology-integrity):

                duplicate link identity detected

                site: ${siteName}
                linkId: ${id}

                first link:
                ${identitiesByLinkId.${id}}

                duplicate link:
                ${linkName}
              ''
            else
              identitiesByLinkId // { "${id}" = linkName; };
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
                    endpoint = endpoints.${nodeName};
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
                        (common.assert_ ((endpoint.node or nodeName) == nodeName) ''
                          invariants(final-topology-integrity):

                          link endpoint node field mismatches endpoint key

                          site: ${siteName}
                          link: ${linkName}
                          endpointKey: ${nodeName}
                          endpoint.node: ${toString (endpoint.node or "<missing>")}
                        '')
                        (
                          common.assert_ ((endpoint.interface or linkName) == linkName) ''
                            invariants(final-topology-integrity):

                            link endpoint interface field mismatches link name

                            site: ${siteName}
                            link: ${linkName}
                            endpointNode: ${nodeName}
                            endpoint.interface: ${toString (endpoint.interface or "<missing>")}
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
          interfaces = node.interfaces or { };
          interfaceNames = sortedNames interfaces;
        in
        lib.forEach interfaceNames (
          ifName:
          let
            iface = interfaces.${ifName};
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
    in
    {
      inherit linkIdToName;
      ok = builtins.deepSeq _linkIdsPresent (
        builtins.deepSeq linkIdToName (builtins.deepSeq _linksOk (builtins.deepSeq _nodesOk true))
      );
    };
}
