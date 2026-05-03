{ lib }:

let
  roleStages = import ../../../lib/fabric/transit-role-stages.nix { };

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

  hasRole = roles: wanted: lib.any (nodeName: roles.${nodeName} == wanted) (builtins.attrNames roles);

  nextRoleOf =
    roles: role:
    roleStages.nextTransitRole {
      inherit role;
      hasDownstreamSelector = hasRole roles "downstream-selector";
      hasUpstreamSelector = hasRole roles "upstream-selector";
    };

  canonicalizeOne =
    {
      siteName,
      roles,
      pair,
    }:
    let
      a0 = toString (builtins.elemAt pair 0);
      b0 = toString (builtins.elemAt pair 1);

      roleA = roles.${a0};
      roleB = roles.${b0};

      rankA = roleStages.transitRank roleA;
      rankB = roleStages.transitRank roleB;

      oriented =
        if rankA < rankB then
          [
            a0
            b0
          ]
        else if rankB < rankA then
          [
            b0
            a0
          ]
        else
          throw ''
            network-forwarding-model: transit ordering cannot connect nodes in the same canonical stage

            site: ${siteName}
            left:  ${a0} (${roleA})
            right: ${b0} (${roleB})
          '';

      src = builtins.elemAt oriented 0;
      dst = builtins.elemAt oriented 1;

      srcRole = roles.${src};
      dstRole = roles.${dst};
      expectedDstRole = nextRoleOf roles srcRole;
    in
    if expectedDstRole == null then
      throw ''
        network-forwarding-model: canonical transit ordering cannot originate from terminal stage

        site: ${siteName}
        node: ${src}
        role: ${srcRole}
      ''
    else if dstRole != expectedDstRole then
      throw ''
        network-forwarding-model: transit ordering violates canonical stage adjacency

        site: ${siteName}
        pair: ${src} -> ${dst}

        sourceRole: ${srcRole}
        destinationRole: ${dstRole}
        expectedDestinationRole: ${expectedDstRole}
      ''
    else
      oriented;

  pairSortKey =
    roles: pair:
    let
      src = toString (builtins.elemAt pair 0);
      dst = toString (builtins.elemAt pair 1);
    in
    "${toString (roleStages.transitRank roles.${src})}|${src}|${dst}";
in
{
  canonicalize =
    {
      siteName,
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
          inherit siteName roles pair;
        }
      ) pairs;
    in
    lib.sort (x: y: (pairSortKey roles x) < (pairSortKey roles y)) orientedPairs;
}
