{ lib, ... }:

{
  derive =
    {
      accessUnitNames,
      accessUnitByTenant,
      allowedUplinksByScope,
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
        scopeNames = builtins.attrNames allowedUplinksByScope;

        # FS-370 / FS-171: a lane binds a **source scope** (tenant or access
        # scope) to the modeled role boundary, and its identity is the scope
        # name, not the access node. The access unit is carried only as the
        # realization binding that owns the ports. Two tenants on one access
        # unit therefore get distinct lanes, and adding an exit to a tenant's
        # `selects` adds a lane/member for that tenant only.
        #
        # FS-315: distinct allow tuples that differ by exit are distinct
        # selection authorities, so there is one lane per (scope, selected
        # exit) — the lane's `uplink` names that exit (FS-322). The
        # upstream-selector owns the ECMP member set across the scope's exits;
        # the realization shall not copy that member set into each sibling lane
        # (FS-315), it forwards each lane's own default to the selector.
        scopeAccessUnit =
          scope: accessUnitByTenant.${scope} or scope;

        downstreamPolicyLane =
          scope:
          if downstreamSelectorUnit == null then
            [ ]
          else
            let
              access = scopeAccessUnit scope;
            in
            [
              {
                a = policyUnit;
                b = downstreamSelectorUnit;
                lane = "scope::${toString scope}";
                laneMeta = {
                  kind = "access";
                  scope = toString scope;
                  access = toString access;
                  uplink = null;
                  uplinks = map toString (allowedUplinksByScope.${scope} or [ ]);
                };
                # The link name is a realization name (it binds to the access
                # unit's ports in inventory), so it stays keyed on the access
                # unit; the lane identity is the scope in laneMeta (FS-171).
                name =
                  canonicalP2pLinkNameForEndpointsWithSuffix policyUnit downstreamSelectorUnit
                    "access-${toString access}";
              }
            ];

        policyUpstreamLanes =
          scope:
          if upstreamSelectorUnit == null then
            [ ]
          else
            let
              access = scopeAccessUnit scope;
            in
            map (
              uplinkName:
              {
                a = policyUnit;
                b = upstreamSelectorUnit;
                lane = "scope::${toString scope}::exit::${toString uplinkName}";
                laneMeta = {
                  kind = "access-uplink";
                  scope = toString scope;
                  access = toString access;
                  uplink = toString uplinkName;
                  uplinks = [ (toString uplinkName) ];
                };
                name =
                  canonicalP2pLinkNameForEndpointsWithSuffix policyUnit upstreamSelectorUnit
                    "access-${toString access}--uplink-${toString uplinkName}";
              }
              // lib.optionalAttrs (builtins.hasAttr (toString uplinkName) overlayNameSet) {
                overlay = toString uplinkName;
              }
            ) (allowedUplinksByScope.${scope} or [ ]);
      in
      (lib.concatMap downstreamPolicyLane scopeNames) ++ (lib.concatMap policyUpstreamLanes scopeNames);
}
