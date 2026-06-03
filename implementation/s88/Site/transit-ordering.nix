{
  lib,
  self ? {
    outPath = ./.;
  },
  ...
}:

let
  roleStages = import (self.outPath + "/implementation/lib/fabric/transit-role-stages.nix") {
    inherit lib self;
  };
  uniqueNodeNames =
    pairs:
    lib.sort (a: b: a < b) (
      lib.unique (
        lib.concatMap (
          pair: if builtins.isList pair && builtins.length pair == 2 then map toString pair else [ ]
        ) pairs
      )
    );

  roleCatalogFrom =
    {
      siteName,
      pairs,
      roleFromInput,
    }:
    let
      nodeNames = uniqueNodeNames pairs;
    in
    builtins.listToAttrs (
      map (
        nodeName:
        let
          role = roleFromInput nodeName;
        in
        if role == null || role == "" then
          throw ''
            network-forwarding-model: transit ordering references node without explicit role

            site: ${siteName}
            node: ${toString nodeName}
          ''
        else
          {
            name = toString nodeName;
            value = toString role;
          }
      ) nodeNames
    );

  canonicalizeOne =
    {
      siteName,
      roles,
      pair,
    }:
    let
      firstEndpoint = toString (builtins.elemAt pair 0);
      secondEndpoint = toString (builtins.elemAt pair 1);

      firstEndpointRole = roles.${firstEndpoint};
      secondEndpointRole = roles.${secondEndpoint};

      firstEndpointRank = roleStages.transitRank firstEndpointRole;
      secondEndpointRank = roleStages.transitRank secondEndpointRole;

      oriented =
        if firstEndpointRank < secondEndpointRank then
          [
            firstEndpoint
            secondEndpoint
          ]
        else if secondEndpointRank < firstEndpointRank then
          [
            secondEndpoint
            firstEndpoint
          ]
        else
          throw ''
            network-forwarding-model: transit ordering cannot connect nodes in the same canonical stage

            site: ${siteName}
            left:  ${firstEndpoint} (${firstEndpointRole})
            right: ${secondEndpoint} (${secondEndpointRole})
          '';

    in
    oriented;

  pairSortKey =
    roles: pair:
    let
      sourceNode = toString (builtins.elemAt pair 0);
      destinationNode = toString (builtins.elemAt pair 1);
    in
    "${toString (roleStages.transitRank roles.${sourceNode})}|${sourceNode}|${destinationNode}";
in
{
  canonicalize =
    {
      siteName,
      site ? { },
      pairs,
      roleFromInput,
    }:
    let
      roles = roleCatalogFrom {
        inherit siteName pairs roleFromInput;
      };

      orientedPairs = map (
        pair:
        canonicalizeOne {
          inherit
            siteName
            roles
            pair
            ;
        }
      ) pairs;
    in
    lib.sort (x: y: (pairSortKey roles x) < (pairSortKey roles y)) orientedPairs;
}
