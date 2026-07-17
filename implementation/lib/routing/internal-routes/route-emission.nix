{ lib }:

{
  build =
    {
      entries,
      intentKind,
      isRuntimeRoutedPrefix,
      laneFields,
      mkRoute4,
      mkRoute6,
      overlayFields,
      preserveExactDsts,
      routeIntent,
      sample,
      summarizedDsts,
      via4,
      via6,
    }:
    let
      mkExactRoute4 =
        dst:
        {
          inherit dst;
          proto = "internal";
          via4 = if via4 != null then via4 else sample.via4;
          intent = routeIntent;
          preserveDst = true;
        }
        // overlayFields
        // laneFields;
      mkExactRoute6 =
        dst:
        {
          inherit dst;
          proto = "internal";
          via6 = if via6 != null then via6 else sample.via6;
          intent = routeIntent;
          preserveDst = true;
        }
        // overlayFields
        // laneFields;
    in
    if isRuntimeRoutedPrefix then
      map (
        entry:
        let
          family = entry.family or sample.family;
          nextHop =
            if family == 4 then
              { via4 = if via4 != null then via4 else entry.via4; }
            else
              { via6 = if via6 != null then via6 else entry.via6; };
        in
        {
          inherit family;
          sourceFile = entry.sourceFile;
          tenant = entry.tenant or entry.netName or null;
          proto = if (entry.overlay or null) != null then "overlay" else "internal";
          intent = {
            kind = intentKind;
            source = "intent-routed-prefix";
            accessNode = entry.owner;
          }
          // lib.optionalAttrs ((entry.authorityClass or null) != null) {
            authorityClass = entry.authorityClass;
          }
          // lib.optionalAttrs ((entry.authorityClass or null) != null) {
            downstreamExport = {
              allowed = (entry.authorityClass or null) != "host-only-provider-prefix";
              reason =
                if (entry.authorityClass or null) == "host-only-provider-prefix" then
                  "host-only-provider-prefix"
                else
                  "authority-class-allows-downstream-export";
            };
          };
        }
        // nextHop
        // builtins.intersectAttrs {
          delegatedPrefixLength = null;
          perTenantPrefixLength = null;
          slot = null;
          prefixPostfix = null;
        } entry
        // lib.optionalAttrs ((entry.prefixName or null) != null) { prefixName = entry.prefixName; }
      ) entries
    else if preserveExactDsts && sample.family == 4 then
      map mkExactRoute4 summarizedDsts
    else if preserveExactDsts && sample.family == 6 then
      map mkExactRoute6 summarizedDsts
    else if sample.family == 4 then
      map (
        dst:
        mkRoute4 {
          inherit dst intentKind;
          via4 = if via4 != null then via4 else sample.via4;
          proto = "internal";
          preserveDst = preserveExactDsts;
        }
      ) summarizedDsts
    else
      map (
        dst:
        mkRoute6 {
          inherit dst intentKind;
          via6 = if via6 != null then via6 else sample.via6;
          proto = "internal";
          preserveDst = preserveExactDsts;
        }
      ) summarizedDsts;
}
