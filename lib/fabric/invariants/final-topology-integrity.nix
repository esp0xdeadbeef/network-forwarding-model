{ lib }:

let
  assert_ = cond: msg: if cond then true else throw msg;

  sortedNames = attrs: lib.sort (a: b: a < b) (builtins.attrNames attrs);

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

      _linksOk =
        lib.forEach linkNames (
          linkName:
          let
            link = links.${linkName};
            members = link.members or [ ];
            endpoints = link.endpoints or { };
            epNodeNames = sortedNames endpoints;
          in
          builtins.seq
            (assert_ (members != [ ] || epNodeNames != [ ]) ''
              invariants(final-topology-integrity):

              link has no members/endpoints

                site: ${siteName}
                link: ${linkName}
            '')
            (builtins.deepSeq
              (lib.forEach members (
                nodeName:
                builtins.seq
                  (assert_ (nodes ? "${nodeName}") ''
                    invariants(final-topology-integrity):

                    link references unknown member node

                      site: ${siteName}
                      link: ${linkName}
                      node: ${nodeName}
                  '')
                  (assert_
                    (nodes.${nodeName}.interfaces or { } ? "${linkName}")
                    ''
                      invariants(final-topology-integrity):

                      link member is missing reverse interface

                        site: ${siteName}
                        link: ${linkName}
                        node: ${nodeName}
                    '')
              ))
              (builtins.deepSeq
                (lib.forEach epNodeNames (
                  nodeName:
                  let
                    ep = endpoints.${nodeName};
                  in
                  builtins.seq
                    (assert_ (nodes ? "${nodeName}") ''
                      invariants(final-topology-integrity):

                      link endpoint references unknown node

                        site: ${siteName}
                        link: ${linkName}
                        endpointNode: ${nodeName}
                    '')
                    (builtins.seq
                      (assert_ ((ep.node or nodeName) == nodeName) ''
                        invariants(final-topology-integrity):

                        link endpoint node field mismatches endpoint key

                          site: ${siteName}
                          link: ${linkName}
                          endpointKey: ${nodeName}
                          endpoint.node: ${toString (ep.node or "<missing>")}
                      '')
                      (assert_
                        ((ep.interface or linkName) == linkName)
                        ''
                          invariants(final-topology-integrity):

                          link endpoint interface field mismatches link name

                            site: ${siteName}
                            link: ${linkName}
                            endpointNode: ${nodeName}
                            endpoint.interface: ${toString (ep.interface or "<missing>")}
                        ''))
                ))
                true))
        );

      _nodesOk =
        lib.forEach nodeNames (
          nodeName:
          let
            node = nodes.${nodeName};
            ifaces = node.interfaces or { };
            ifNames = sortedNames ifaces;
          in
          lib.forEach ifNames (
            ifName:
            builtins.seq
              (assert_ (links ? "${ifName}") ''
                invariants(final-topology-integrity):

                node interface references unknown link

                  site: ${siteName}
                  node: ${nodeName}
                  interface: ${ifName}
              '')
              (let
                link = links.${ifName};
                members = link.members or [ ];
                endpoints = link.endpoints or { };
              in
              assert_
                ((lib.elem nodeName members) || (endpoints ? "${nodeName}"))
                ''
                  invariants(final-topology-integrity):

                  node interface is orphaned from link membership

                    site: ${siteName}
                    node: ${nodeName}
                    interface: ${ifName}
                '')
          )
        );
    in
    builtins.deepSeq _linksOk (builtins.deepSeq _nodesOk true);
}
