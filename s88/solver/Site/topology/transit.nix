{ lib }:

let
  ip = import ../../../../lib/net/ip-utils.nix { inherit lib; };

  stripMask = ip.stripMask;

  sortedPair =
    a: b:
    if a < b then
      {
        left = a;
        right = b;
      }
    else
      {
        left = b;
        right = a;
      };

  pairKey =
    a: b:
    let
      p = sortedPair a b;
    in
    "${p.left}|${p.right}";

  looksLikeStableLinkId = x: builtins.isString x && lib.hasPrefix "link::" (toString x);

  normalizeInputOrdering =
    {
      siteName,
      ordering,
    }:
    let
      _list =
        if builtins.isList ordering then
          true
        else
          throw ''
            network-forwarding-model: malformed transit.ordering input

            site: ${siteName}

            expected:
              transit.ordering = [ [ "<from-node>" "<to-node>" ] ... ]

            got:
              ${builtins.typeOf ordering}
          '';

      entryKind =
        x:
        if builtins.isList x && builtins.length x == 2 then
          "pair"
        else if looksLikeStableLinkId x then
          "stable-link-id"
        else if builtins.isString x then
          "string"
        else
          "invalid";

      kinds = lib.unique (map entryKind ordering);

      _shape =
        if ordering == [ ] || kinds == [ "pair" ] then
          true
        else if kinds == [ "stable-link-id" ] then
          throw ''
            network-forwarding-model: malformed transit.ordering input

            site: ${siteName}

            stable link identities are output-only.
            input transit.ordering must be a list of directed node pairs:

              [ [ "<from-node>" "<to-node>" ] ... ]
          ''
        else if kinds == [ "string" ] then
          throw ''
            network-forwarding-model: malformed transit.ordering input

            site: ${siteName}

            each entry must be a 2-element directed node pair:

              [ "<from-node>" "<to-node>" ]
          ''
        else
          throw ''
            network-forwarding-model: malformed transit.ordering input

            site: ${siteName}

            expected:
              transit.ordering = [ [ "<from-node>" "<to-node>" ] ... ]

            got entry kinds:
              ${builtins.toJSON kinds}
          '';

      normalizeOne =
        idx: entry:
        if !(builtins.isList entry) then
          throw ''
            network-forwarding-model: malformed transit.ordering entry

            site: ${siteName}
            index: ${toString idx}

            expected:
              [ "<from-node>" "<to-node>" ]

            got:
              ${builtins.typeOf entry}
          ''
        else
          let
            len = builtins.length entry;
          in
          if len != 2 then
            throw ''
              network-forwarding-model: malformed transit.ordering entry

              site: ${siteName}
              index: ${toString idx}

              expected:
                [ "<from-node>" "<to-node>" ]

              got:
                ${builtins.toJSON entry}
            ''
          else
            let
              a = toString (builtins.elemAt entry 0);
              b = toString (builtins.elemAt entry 1);
            in
            if a == "" || b == "" then
              throw ''
                network-forwarding-model: malformed transit.ordering entry

                site: ${siteName}
                index: ${toString idx}

                expected non-empty node names:
                  [ "<from-node>" "<to-node>" ]

                got:
                  ${builtins.toJSON entry}
              ''
            else if a == b then
              throw ''
                network-forwarding-model: transit.ordering must not contain self-links

                site: ${siteName}
                node: ${a}
              ''
            else
              [
                a
                b
              ];

      pairs = lib.imap0 normalizeOne ordering;

      _unique = builtins.foldl' (
        acc: pair:
        let
          a = builtins.elemAt pair 0;
          b = builtins.elemAt pair 1;
          k = pairKey a b;
          rendered = builtins.toJSON [
            a
            b
          ];
        in
        if acc ? "${k}" then
          throw ''
            network-forwarding-model: duplicate node-pair transit.ordering entry

            site: ${siteName}

            first:
              ${acc.${k}}

            duplicate:
              ${rendered}
          ''
        else
          acc // { "${k}" = rendered; }
      ) { } pairs;
    in
    builtins.deepSeq _unique {
      inputShape = "node-pairs";
      pairs = pairs;
    };

  transitAdjacenciesFromLinks =
    links:
    let
      linkNames = lib.sort (a: b: a < b) (builtins.attrNames links);
      p2pLinkNames = lib.filter (linkName: (links.${linkName}.kind or null) == "p2p") linkNames;

      mkEndpoint =
        nodeName: ep:
        let
          local4 = if (ep.addr4 or null) == null then null else stripMask ep.addr4;
          local6 = if (ep.addr6 or null) == null then null else stripMask ep.addr6;
        in
        if local4 == null then
          throw ''
            network-forwarding-model: transit adjacency endpoint requires IPv4 local address

            link: ${toString (ep.interface or "<unknown-link>")}
            unit: ${toString nodeName}
            addr4: ${toString (ep.addr4 or "null")}
          ''
        else
          {
            unit = nodeName;
            local = {
              ipv4 = local4;
            }
            // lib.optionalAttrs (local6 != null) { ipv6 = local6; };
          };

      mkAdjacency =
        linkName:
        let
          link = links.${linkName};
          linkId = link.id or null;
          endpoints = link.endpoints or { };
          nodeNames = lib.sort (a: b: a < b) (builtins.attrNames endpoints);

          _two =
            if builtins.length nodeNames == 2 then
              true
            else
              throw ''
                network-forwarding-model: transit adjacency must have exactly 2 endpoints

                link: ${linkName}
                endpoints: ${builtins.toJSON nodeNames}
              '';

          _id =
            if linkId == null then
              throw ''
                network-forwarding-model: transit adjacency is missing stable link identity

                link: ${linkName}
              ''
            else
              true;
        in
        builtins.seq _two (
          builtins.seq _id {
            id = toString linkId;
            name = linkName;
            kind = "p2p";
            link = linkName;
            members = nodeNames;
            endpoints = map (nodeName: mkEndpoint nodeName endpoints.${nodeName}) nodeNames;
          }
        );
    in
    map mkAdjacency p2pLinkNames;

  transitLinkIdForPair =
    links: pair:
    let
      a = toString (builtins.elemAt pair 0);
      b = toString (builtins.elemAt pair 1);
      members = sortedPair a b;

      _self =
        if a == b then
          throw ''
            network-forwarding-model: transit.ordering must not contain self-links

            node: ${a}
          ''
        else
          true;

      hits = lib.filter (
        linkName:
        let
          l = links.${linkName};
          ms = lib.sort (x: y: x < y) (l.members or [ ]);
        in
        (l.kind or null) == "p2p"
        && builtins.length ms == 2
        && (builtins.elemAt ms 0) == members.left
        && (builtins.elemAt ms 1) == members.right
      ) (builtins.attrNames links);

      _known =
        if hits == [ ] then
          throw ''
            network-forwarding-model: transit.ordering node pair references unknown realized p2p adjacency

            pair: ${a} <-> ${b}
          ''
        else
          true;

      _unique =
        if builtins.length hits == 1 then
          true
        else
          throw ''
            network-forwarding-model: transit.ordering node pair is ambiguous against realized p2p adjacencies

            pair: ${a} <-> ${b}
            links: ${builtins.toJSON hits}
          '';

      linkName = builtins.head hits;
      linkId = links.${linkName}.id or null;

      _id =
        if linkId == null then
          throw ''
            network-forwarding-model: transit link is missing stable identity

            link: ${linkName}
          ''
        else
          true;
    in
    builtins.seq _self (
      builtins.seq _known (builtins.seq _unique (builtins.seq _id (toString linkId)))
    );

in
{
  inherit
    normalizeInputOrdering
    transitAdjacenciesFromLinks
    transitLinkIdForPair
    ;
}
