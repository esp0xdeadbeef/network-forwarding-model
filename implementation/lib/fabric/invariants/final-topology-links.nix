{ lib, self ? { outPath = ./.; }, ... }:

let
  common = import ./common.nix { inherit lib self; };
  linkIdentities = import
    (
      self.outPath + "/implementation/lib/fabric/invariants/final-topology-links/link-identities.nix"
    )
    { inherit lib self; };

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
    { siteName
    , nodes
    , links
    ,
    }:
    let
      linkNames = sortedNames links;
      nodeNames = sortedNames nodes;

      identityCheck = linkIdentities.validate { inherit siteName links linkNames; };
      linkIdToName = identityCheck.byId;

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
                builtins.deepSeq
                  (lib.forEach epNodeNames (
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
                  ))
                  true
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
      ok = builtins.seq identityCheck.ok (builtins.deepSeq _linksOk (builtins.deepSeq _nodesOk true));
    };
}
