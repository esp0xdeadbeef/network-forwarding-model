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
      isRuntimeRoutedPrefix = sample.kind == "runtime-routed-prefix";
      entryDsts = lib.unique (map (e: e.dst) (lib.filter (e: e ? dst) entries));
      aggDst =
        if isRuntimeRoutedPrefix then
          null
        else if sample.kind == "p2p" then
          null
        else if mode == "none" && sample.kind != "p2p" then
          null
        else if sample.kind == "tenant" then
          helpers.buildTenantAggregate topo sample.family
        else
          null;
      summarizedDsts =
        if sample.kind == "overlay" || sample.kind == "p2p" then
          entryDsts
        else if builtins.length entryDsts <= 1 then
          entryDsts
        else
          helpers.summarizeCidrs sample.family entryDsts;
      intentKind =
        if isRuntimeRoutedPrefix then
          "runtime-routed-prefix-return"
        else if sample.kind == "overlay" then
          "overlay-reachability"
        else
          "internal-reachability";

      rawRoutes =
        if isRuntimeRoutedPrefix then
          map (entry: {
            family = 6;
            sourceFile = entry.sourceFile;
            proto = if (entry.overlay or null) != null then "overlay" else "internal";
            via6 = entry.via6;
            intent = {
              kind = intentKind;
              source = "intent-routed-prefix";
              accessNode = entry.owner;
            };
          } // lib.optionalAttrs ((entry.prefixName or null) != null) { prefixName = entry.prefixName; })
            entries
        else if sample.family == 4 then
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
