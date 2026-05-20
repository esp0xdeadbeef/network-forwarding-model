{ lib, ... }:

{
  derive =
    { accessUnitNames
    , allowedUplinksByAccessUnit
    , canonicalP2pLinkNameForEndpointsWithSuffix
    , downstreamSelectorUnit
    , overlayNameSet
    , policyUnit
    , upstreamSelectorUnit
    ,
    }:
    if policyUnit == null then
      [ ]
    else
      let
        downstreamPolicyLane =
          accessUnit:
          if downstreamSelectorUnit == null then
            [ ]
          else
            [
              {
                a = policyUnit;
                b = downstreamSelectorUnit;
                lane = "access::${toString accessUnit}";
                laneMeta = {
                  kind = "access";
                  access = toString accessUnit;
                  uplink = null;
                  uplinks = [ ];
                };
                name =
                  canonicalP2pLinkNameForEndpointsWithSuffix policyUnit downstreamSelectorUnit
                    "access-${toString accessUnit}";
              }
            ];

        policyUpstreamLanes =
          accessUnit:
          let
            uplinks = allowedUplinksByAccessUnit.${toString accessUnit} or [ ];
          in
          if upstreamSelectorUnit == null then
            [ ]
          else
            map
              (
                uplinkName:
                {
                  a = policyUnit;
                  b = upstreamSelectorUnit;
                  lane = "access::${toString accessUnit}::uplink::${toString uplinkName}";
                  laneMeta = {
                    kind = "access-uplink";
                    access = toString accessUnit;
                    uplink = toString uplinkName;
                    uplinks = [ (toString uplinkName) ];
                  };
                  name =
                    canonicalP2pLinkNameForEndpointsWithSuffix policyUnit upstreamSelectorUnit
                      "access-${toString accessUnit}--uplink-${toString uplinkName}";
                }
                // lib.optionalAttrs (builtins.hasAttr (toString uplinkName) overlayNameSet) {
                  overlay = toString uplinkName;
                }
              )
              uplinks;
      in
      (lib.concatMap downstreamPolicyLane accessUnitNames)
      ++ (lib.concatMap policyUpstreamLanes accessUnitNames);
}
