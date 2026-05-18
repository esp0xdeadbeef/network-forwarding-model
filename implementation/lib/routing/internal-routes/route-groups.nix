{ lib, self ? { outPath = ./.; }, ... }:

let
  helpers = import (self.outPath + "/implementation/lib/routing/static-helpers.nix") { inherit lib self; };

in
{
  build =
    {
      topo,
      mode,
      entries,
      mkRoute4,
      mkRoute6,
    }:
    let
      sample = builtins.head entries;
      entryDsts = lib.unique (map (e: e.dst) entries);
      aggDst =
        if mode == "none" && sample.kind != "p2p" then
          null
        else if sample.kind == "p2p" then
          helpers.buildP2pAggregate topo sample.family
        else if sample.kind == "tenant" then
          helpers.buildTenantAggregate topo sample.family
        else
          null;
      summarizedDsts =
        if sample.kind == "p2p" && aggDst != null then
          [ ]
        else if sample.kind == "overlay" || sample.kind == "p2p" then
          entryDsts
        else if builtins.length entryDsts <= 1 then
          entryDsts
        else
          helpers.summarizeCidrs sample.family entryDsts;
      intentKind = if sample.kind == "overlay" then "overlay-reachability" else "internal-reachability";

      rawRoutes =
        if sample.family == 4 then
          map (
            dst:
            mkRoute4 {
              inherit dst intentKind;
              via4 = sample.via4;
              proto = "internal";
              preserveDst = sample.kind == "p2p" || sample.kind == "overlay";
            }
          ) summarizedDsts
        else
          map (
            dst:
            mkRoute6 {
              inherit dst intentKind;
              via6 = sample.via6;
              proto = "internal";
              preserveDst = sample.kind == "p2p" || sample.kind == "overlay";
            }
          ) summarizedDsts;

      aggRoute =
        if aggDst == null then
          [ ]
        else if sample.family == 4 then
          [ (mkRoute4 { dst = aggDst; via4 = sample.via4; proto = "internal"; inherit intentKind; }) ]
        else
          [ (mkRoute6 { dst = aggDst; via6 = sample.via6; proto = "internal"; inherit intentKind; }) ];
    in
    {
      linkName = sample.linkName;
      routes4 = if sample.family == 4 then rawRoutes ++ aggRoute else [ ];
      routes6 = if sample.family == 6 then rawRoutes ++ aggRoute else [ ];
    };
}
