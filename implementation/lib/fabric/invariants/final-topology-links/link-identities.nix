{ lib, self ? { outPath = ./.; }, ... }:

let
  common = import (self.outPath + "/implementation/lib/fabric/invariants/common.nix") { inherit lib self; };

in
{
  validate =
    { siteName
    , links
    , linkNames
    ,
    }:
    let
      _present = lib.forEach linkNames (
        linkName:
        common.assert_ ((links.${linkName}.id or null) != null) ''
          invariants(final-topology-integrity):

          link is missing stable identity

          site: ${siteName}
          link: ${linkName}
        ''
      );

      byId =
        builtins.foldl'
          (
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
                identitiesByLinkId // { "${id}" = linkName; }
          )
          { }
          linkNames;
    in
    {
      inherit byId;
      ok = builtins.deepSeq _present (builtins.deepSeq byId true);
    };
}
