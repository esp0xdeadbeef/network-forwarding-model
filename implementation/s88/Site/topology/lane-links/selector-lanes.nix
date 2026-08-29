{ lib, ... }:

{
  derive =
    {
      accessUnitNames,
      allowedUplinksByAccessUnit,
      canonicalP2pLinkNameForEndpointsWithSuffix,
      downstreamSelectorUnit,
      overlayNameSet,
      policyUnit,
      upstreamSelectorUnit,
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
          else if builtins.length uplinks <= 1 then
            map (
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
            ) uplinks
          else
            # A multi-uplink access unit keeps ONE policy->upstream-selector
            # lane. The upstream-selector owns the multi-WAN/load-balancing
            # choice across the permitted cores (URS: "Upstream selectors ...
            # load balancing ... realize permitted paths"). Splitting this
            # into per-uplink lanes would move that choice into the policy
            # point, which is not its role.
            [
              {
                a = policyUnit;
                b = upstreamSelectorUnit;
                lane = "access::${toString accessUnit}";
                laneMeta = {
                  kind = "access-uplink";
                  access = toString accessUnit;
                  uplink = null;
                  uplinks = map toString uplinks;
                };
                name =
                  canonicalP2pLinkNameForEndpointsWithSuffix policyUnit upstreamSelectorUnit
                    "access-${toString accessUnit}";
              }
            ];
      in
      (lib.concatMap downstreamPolicyLane accessUnitNames)
      ++ (lib.concatMap policyUpstreamLanes accessUnitNames);
}
