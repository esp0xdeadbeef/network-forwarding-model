{ lib, ... }:

{
  annotate =
    { accessUnitNames
    , canonicalP2pLinkNameForEndpoints
    , downstreamSelectorUnit
    , linkSpecConnectsEndpoints
    ,
    }:
    pair:
    let
      matchingAccessUnits =
        lib.filter
          (
            accessUnit:
            downstreamSelectorUnit != null && linkSpecConnectsEndpoints accessUnit downstreamSelectorUnit pair
          )
          accessUnitNames;
    in
    if builtins.length matchingAccessUnits != 1 then
      pair
    else
      {
        a = if builtins.isList pair then toString (builtins.elemAt pair 0) else toString pair.a;
        b = if builtins.isList pair then toString (builtins.elemAt pair 1) else toString pair.b;
        name =
          if builtins.isAttrs pair && (pair.name or null) != null then
            pair.name
          else
            canonicalP2pLinkNameForEndpoints
              (if builtins.isList pair then builtins.elemAt pair 0 else pair.a)
              (if builtins.isList pair then builtins.elemAt pair 1 else pair.b);
      }
      // lib.optionalAttrs (builtins.isAttrs pair && (pair.lane or null) != null) { lane = pair.lane; }
      // lib.optionalAttrs (builtins.isAttrs pair && (pair.overlay or null) != null) { overlay = pair.overlay; }
      // lib.optionalAttrs (builtins.isAttrs pair && (pair.uplinks or null) != null) { uplinks = pair.uplinks; }
      // {
        laneMeta = {
          kind = "access-edge";
          # FS-171: the lane identity is the source scope. The access-edge lane is
          # shared by the access unit's tenants, so it carries the scope list it
          # serves (the access unit itself is a scope here) plus the access
          # realization binding.
          scope = builtins.head matchingAccessUnits;
          scopes = matchingAccessUnits;
          access = builtins.head matchingAccessUnits;
          uplink = null;
          uplinks = [ ];
        };
      };
}
