{ lib }:

let
  common = import ./common.nix { inherit lib; };

  sorted = xs: lib.sort (a: b: a < b) xs;

  nodeNamesByRole =
    role: nodes: sorted (builtins.attrNames (lib.filterAttrs (_: n: (n.role or null) == role) nodes));

  hasP2pLinkBetween =
    links: a: b:
    lib.any (
      linkName:
      let
        l = links.${linkName};
        members = l.members or [ ];
      in
      (l.kind or null) == "p2p" && lib.elem a members && lib.elem b members
    ) (builtins.attrNames links);

in
{
  check =
    { site }:
    let
      siteName = toString (site.siteName or "<unknown-site>");
      nodes = site.nodes or { };
      links = site.links or { };

      coreNodes = nodeNamesByRole "core" nodes;
      accessNodes = nodeNamesByRole "access" nodes;
      policyNodes = nodeNamesByRole "policy" nodes;
      selectorNodes = nodeNamesByRole "upstream-selector" nodes;

      policyNode = if policyNodes == [ ] then null else builtins.head policyNodes;

      selectorNode = if selectorNodes == [ ] then null else builtins.head selectorNodes;

      _policyCount = common.assert_ (builtins.length policyNodes == 1) ''
        invariants(transit-ordering-valid):

        expected exactly one policy node

          site: ${siteName}
          found: ${toString (builtins.length policyNodes)}
      '';

      _selectorCount = common.assert_ (builtins.length selectorNodes <= 1) ''
        invariants(transit-ordering-valid):

        expected at most one upstream-selector node

          site: ${siteName}
          found: ${toString (builtins.length selectorNodes)}
      '';

      _coreCount = common.assert_ (coreNodes != [ ]) ''
        invariants(transit-ordering-valid):

        expected at least one core node

          site: ${siteName}
      '';

      _coresToSelector =
        if selectorNode == null then
          true
        else
          builtins.deepSeq (lib.forEach coreNodes (
            coreNode:
            common.assert_ (hasP2pLinkBetween links coreNode selectorNode) ''
              invariants(transit-ordering-valid):

              missing core -> upstream-selector p2p adjacency

                site: ${siteName}
                core: ${coreNode}
                upstream-selector: ${selectorNode}
            ''
          )) true;

      _selectorToPolicy =
        if selectorNode == null || policyNode == null then
          true
        else
          common.assert_ (hasP2pLinkBetween links selectorNode policyNode) ''
            invariants(transit-ordering-valid):

            missing upstream-selector -> policy p2p adjacency

              site: ${siteName}
              upstream-selector: ${selectorNode}
              policy: ${policyNode}
          '';

      _policyToAccess = builtins.deepSeq (lib.forEach accessNodes (
        accessNode:
        common.assert_ (hasP2pLinkBetween links policyNode accessNode) ''
          invariants(transit-ordering-valid):

          missing policy -> access p2p adjacency

            site: ${siteName}
            policy: ${policyNode}
            access: ${accessNode}
        ''
      )) true;

    in
    builtins.seq _policyCount (
      builtins.seq _selectorCount (
        builtins.seq _coreCount (
          builtins.seq _coresToSelector (builtins.seq _selectorToPolicy (builtins.seq _policyToAccess true))
        )
      )
    );
}
