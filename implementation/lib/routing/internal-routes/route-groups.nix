{ lib, self ? { outPath = ./.; }, ... }:

let
  helpers = import (self.outPath + "/implementation/lib/routing/static-helpers.nix") { inherit lib self; };
  uniqueStrings =
    xs:
    builtins.attrNames (builtins.listToAttrs (map (x: {
      name = x;
      value = true;
    }) xs));

in
{
  build =
    { topo
    , mode
    , entries
    , mkRoute4
    , mkRoute6
    , linkName ? null
    , via4 ? null
    , via6 ? null
    ,
    }:
      let
        sample = builtins.head entries;
        isRuntimeRoutedPrefix = sample.kind == "runtime-routed-prefix";
      entryDsts = uniqueStrings (map (e: e.dst) (builtins.filter (e: e ? dst) entries));
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
      preserveExactDsts = mode == "none" || sample.kind == "overlay" || sample.kind == "p2p";
      summarizedDsts =
        if preserveExactDsts then
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
      routeIntent = {
        kind = intentKind;
      };
      overlayFields =
        lib.optionalAttrs ((sample.overlay or null) != null) {
          overlay = sample.overlay;
        }
        // lib.optionalAttrs ((sample.peerSite or null) != null) {
          peerSite = sample.peerSite;
        };
      linkMeta =
        if linkName != null && builtins.hasAttr linkName (topo.links or { }) then
          ((topo.links.${linkName}.laneMeta or { }))
        else
          { };
      laneFields =
        lib.optionalAttrs (sample.kind == "overlay" && (linkMeta.access or null) != null) {
          lane = {
            access = linkMeta.access;
            uplink = if (linkMeta.uplink or null) != null then linkMeta.uplink else (sample.overlay or null);
          };
        };
      mkExactRoute4 =
        dst: {
          inherit dst;
          proto = "internal";
          via4 = if via4 != null then via4 else sample.via4;
          intent = routeIntent;
          preserveDst = true;
        } // overlayFields // laneFields;
      mkExactRoute6 =
        dst: {
          inherit dst;
          proto = "internal";
          via6 = if via6 != null then via6 else sample.via6;
          intent = routeIntent;
          preserveDst = true;
        } // overlayFields // laneFields;

      rawRoutes =
        if isRuntimeRoutedPrefix then
          map
            (entry: {
              family = 6;
              sourceFile = entry.sourceFile;
              proto = if (entry.overlay or null) != null then "overlay" else "internal";
              via6 = if via6 != null then via6 else entry.via6;
              intent = {
                kind = intentKind;
                source = "intent-routed-prefix";
                accessNode = entry.owner;
              };
            } // lib.optionalAttrs ((entry.prefixName or null) != null) { prefixName = entry.prefixName; })
            entries
        else if preserveExactDsts && sample.family == 4 then
          map mkExactRoute4 summarizedDsts
        else if preserveExactDsts && sample.family == 6 then
          map mkExactRoute6 summarizedDsts
        else if sample.family == 4 then
          map
            (
              dst:
              mkRoute4 {
                inherit dst intentKind;
                via4 = if via4 != null then via4 else sample.via4;
                proto = "internal";
                preserveDst = preserveExactDsts;
              }
            )
            summarizedDsts
        else
          map
            (
              dst:
              mkRoute6 {
                inherit dst intentKind;
                via6 = if via6 != null then via6 else sample.via6;
                proto = "internal";
                preserveDst = preserveExactDsts;
              }
            )
            summarizedDsts;

      aggRoute =
        if aggDst == null then
          [ ]
        else if sample.family == 4 then
          [ (mkRoute4 { dst = aggDst; via4 = if via4 != null then via4 else sample.via4; proto = "internal"; inherit intentKind; }) ]
        else
          [ (mkRoute6 { dst = aggDst; via6 = if via6 != null then via6 else sample.via6; proto = "internal"; inherit intentKind; }) ];
    in
    {
      linkName = if linkName != null then linkName else sample.linkName;
      routes4 = if sample.family == 4 then rawRoutes ++ aggRoute else [ ];
      routes6 = if sample.family == 6 then rawRoutes ++ aggRoute else [ ];
    };
}
