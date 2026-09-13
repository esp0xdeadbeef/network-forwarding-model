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
          else
            # One access-uplink lane PER permitted uplink. FS-370-SMS-050: a lane
            # with kind "access-uplink" shall carry a non-null uplink field
            # matching the intent's to.uplinks[] value, and the CPM shall not
            # silently drop uplink annotations for tenants with explicit
            # allow-{tenant}-to-{uplink} rules. The upstream selector still
            # realizes the choice AMONG these permitted uplinks (URS: upstream
            # selectors realize permitted paths, they do not create policy);
            # modeling one lane per permitted uplink does not move that choice
            # into the policy point.
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
                };
                name =
                  canonicalP2pLinkNameForEndpointsWithSuffix policyUnit upstreamSelectorUnit
                    "access-${toString accessUnit}--uplink-${toString uplinkName}";
              }
              // lib.optionalAttrs (builtins.hasAttr (toString uplinkName) overlayNameSet) {
                overlay = toString uplinkName;
              }
            ) uplinks;
      in
      (lib.concatMap downstreamPolicyLane accessUnitNames)
      ++ (lib.concatMap policyUpstreamLanes accessUnitNames);
}
