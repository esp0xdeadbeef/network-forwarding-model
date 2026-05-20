{ lib, self ? { outPath = ./.; }, ... }:

let
  roleStages = import (self.outPath + "/implementation/lib/fabric/transit-role-stages.nix") { inherit lib self; };

in
{
  build =
    { enterprise
    , siteId
    , rolesResult
    , realizedTransitAdjacencies
    ,
    }:
    let
      orderKey =
        adj:
        let
          members = adj.members or [ ];
          memberA = toString (builtins.elemAt members 0);
          memberB = toString (builtins.elemAt members 1);
          memberARank = roleStages.transitRankOrFallback 9 (rolesResult.roleFromInput memberA);
          memberBRank = roleStages.transitRankOrFallback 9 (rolesResult.roleFromInput memberB);
          oriented =
            if memberARank < memberBRank then
              { src = memberA; dst = memberB; rank = memberARank; }
            else
              { src = memberB; dst = memberA; rank = memberBRank; };
        in
        "${toString oriented.rank}|${oriented.src}|${oriented.dst}|${toString (adj.name or "")}";

      p2pAdjacencies = lib.filter (adj: (adj.kind or null) == "p2p") realizedTransitAdjacencies;
      orderedIds = map (adj: toString adj.id) (
        lib.sort (a: b: (orderKey a) < (orderKey b)) p2pAdjacencies
      );

      expectedIds = lib.sort (a: b: a < b) (map (adj: toString adj.id) realizedTransitAdjacencies);
      actualIds = lib.sort (a: b: a < b) orderedIds;

      uniqueOrdering =
        if (builtins.length orderedIds) == (builtins.length (lib.unique orderedIds)) then
          true
        else
          throw ''
            network-forwarding-model: transit.ordering contains duplicate link identities

            site: ${enterprise}.${siteId}
            ordering: ${builtins.toJSON orderedIds}
          '';

      completeOrdering =
        if actualIds == expectedIds then
          true
        else
          throw ''
            network-forwarding-model: transit.ordering is incomplete or inconsistent with realized topology

            site: ${enterprise}.${siteId}
            expected: ${builtins.toJSON expectedIds}
            actual: ${builtins.toJSON actualIds}
          '';
    in
    builtins.seq uniqueOrdering (builtins.seq completeOrdering orderedIds);
}
