{ lib }:

let
  common = import ./common.nix { inherit lib; };
  roleStages = import ../transit-role-stages.nix { };

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

  p2pLinkNames =
    links: lib.filter (linkName: (links.${linkName}.kind or null) == "p2p") (builtins.attrNames links);

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
      downstreamNodes = nodeNamesByRole "downstream-selector" nodes;
      selectorNodes = nodeNamesByRole "upstream-selector" nodes;

      policyNode = if policyNodes == [ ] then null else builtins.head policyNodes;
      downstreamNode = if downstreamNodes == [ ] then null else builtins.head downstreamNodes;
      selectorNode = if selectorNodes == [ ] then null else builtins.head selectorNodes;

      _policyCount = common.assert_ (builtins.length policyNodes == 1) ''
        invariants(transit-ordering-valid):

        expected exactly one policy node

        site: ${siteName}
        found: ${toString (builtins.length policyNodes)}
      '';

      _downstreamCount = common.assert_ (builtins.length downstreamNodes <= 1) ''
        invariants(transit-ordering-valid):

        expected at most one downstream-selector node

        site: ${siteName}
        found: ${toString (builtins.length downstreamNodes)}
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

      expectedAdjacencies = roleStages.expectedTransitAdjacencies {
        inherit accessNodes coreNodes downstreamNode policyNode;
        upstreamSelectorNode = selectorNode;
      };

      _expectedAdjacenciesPresent = builtins.deepSeq (
        lib.forEach expectedAdjacencies (
          adjacency:
          common.assert_ (hasP2pLinkBetween links adjacency.source adjacency.target) ''
            invariants(transit-ordering-valid):

            missing ${adjacency.sourceRole} -> ${adjacency.targetRole} p2p adjacency

            site: ${siteName}
            source: ${adjacency.source}
            target: ${adjacency.target}
          ''
        )
      ) true;

      transitLinks = sorted (p2pLinkNames links);

      transitLinkIds = map (linkName: toString (links.${linkName}.id or "")) transitLinks;

      ordering = ((site.transit or { }).ordering or null);

      _orderingPresent =
        if transitLinks == [ ] then
          true
        else
          common.assert_ (ordering != null && builtins.isList ordering) ''
            invariants(transit-ordering-valid):

            transit.ordering must be present and expressed as link identities

            site: ${siteName}
          '';

      _p2pIdsPresent = lib.forEach transitLinks (
        linkName:
        common.assert_ ((links.${linkName}.id or null) != null) ''
          invariants(transit-ordering-valid):

          p2p link is missing stable identity

          site: ${siteName}
          link: ${linkName}
        ''
      );

      _orderingKnown =
        if ordering == null || !(builtins.isList ordering) then
          true
        else
          lib.forEach ordering (
            linkId:
            common.assert_ (lib.elem (toString linkId) transitLinkIds) ''
              invariants(transit-ordering-valid):

              transit.ordering references unknown transit link identity

              site: ${siteName}
              linkId: ${toString linkId}
            ''
          );

      _orderingUnique =
        if ordering == null || !(builtins.isList ordering) then
          true
        else
          common.assert_
            ((builtins.length ordering) == (builtins.length (lib.unique (map toString ordering))))
            ''
              invariants(transit-ordering-valid):

              transit.ordering contains duplicate link identities

              site: ${siteName}
              ordering: ${builtins.toJSON ordering}
            '';

      _orderingComplete =
        if ordering == null || !(builtins.isList ordering) then
          true
        else
          common.assert_ (sorted (map toString ordering) == sorted transitLinkIds) ''
            invariants(transit-ordering-valid):

            transit.ordering is incomplete or inconsistent with topology

            site: ${siteName}
            expected: ${builtins.toJSON (sorted transitLinkIds)}
            got: ${builtins.toJSON (sorted (map toString ordering))}
          '';
    in
    builtins.seq _policyCount (
      builtins.seq _downstreamCount (
        builtins.seq _selectorCount (
          builtins.seq _coreCount (
            builtins.seq _expectedAdjacenciesPresent (
              builtins.seq _orderingPresent (
                builtins.deepSeq _p2pIdsPresent (
                  builtins.deepSeq _orderingKnown (builtins.seq _orderingUnique (builtins.seq _orderingComplete true))
                )
              )
            )
          )
        )
      )
    );
}
