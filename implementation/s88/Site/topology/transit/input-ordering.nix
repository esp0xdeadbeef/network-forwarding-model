{ lib, self ? { outPath = ./.; }, ... }:

let
  pairsMod = import (self.outPath + "/implementation/s88/Site/topology/transit/pairs.nix") { inherit lib self; };

in
{
  normalize =
    { siteName
    , ordering
    ,
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
        else if pairsMod.looksLikeStableLinkId x then
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

      normalizedPairs = lib.imap0 normalizeOne ordering;

      _unique = builtins.foldl'
        (
          acc: pair:
            let
              a = builtins.elemAt pair 0;
              b = builtins.elemAt pair 1;
              k = pairsMod.pairKey a b;
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
        )
        { }
        normalizedPairs;
    in
    builtins.deepSeq _unique {
      inputShape = "node-pairs";
      pairs = normalizedPairs;
    };
}
