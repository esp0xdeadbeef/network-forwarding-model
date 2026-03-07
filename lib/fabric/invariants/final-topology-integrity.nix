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

      nodeNames = sortedNames nodes;
      linkNames = sortedNames links;

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
    in
    builtins.deepSeq _linksOk (builtins.deepSeq _nodesOk true);
}
