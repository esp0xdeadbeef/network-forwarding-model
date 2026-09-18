{ lib, ... }:

{
  derive =
    {
      accessUnitNames,
      accessUnitByTenant,
      allowedUplinksByScope,
      canonicalP2pLinkNameForEndpointsWithSuffix,
      downstreamSelectorUnit,
      ingressTargetAccessUnits,
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

        # The access<->downstream<->policy transport lane is one per **access
        # unit** (FS-260: access reaches the policy point as access <->
        # downstream-selector <-> policy). It is fabric transport, not a
        # per-scope selection lane; the per-scope egress selection lives on the
        # policy<->upstream-selector lane below.
        downstreamPolicyLane =
          access:
          if downstreamSelectorUnit == null then
            [ ]
          else
            [
              {
                a = policyUnit;
                b = downstreamSelectorUnit;
                lane = "access::${toString access}";
                laneMeta = {
                  kind = "access";
                  scope = toString access;
                  access = toString access;
                  uplink = null;
                  uplinks = [ ];
                };
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
      let
        # FS-210/FS-230: the ingress/return lane for a public-ingress target
        # access. It is a transport lane to the access (uplink = null), not an
        # exit selection, so it grants no default/NAT/outbound authority to that
        # access. Emit only for access units that do not already have a
        # scope-emitted policy<->upstream-selector lane, to avoid duplicates.
        lanesFromScopes = lib.concatMap policyUpstreamLanes scopeNames;
        accessUnitsWithScopeLane = lib.unique (
          map (l: l.laneMeta.access) (
            lib.filter (l: builtins.isAttrs (l.laneMeta or null)) lanesFromScopes
          )
        );
        ingressLaneForAccess =
          access:
          if upstreamSelectorUnit == null || builtins.elem (toString access) accessUnitsWithScopeLane then
            [ ]
          else
            [
              {
                a = policyUnit;
                b = upstreamSelectorUnit;
                lane = "ingress-return::${toString access}";
                laneMeta = {
                  kind = "access-uplink";
                  scope = toString access;
                  access = toString access;
                  uplink = null;
                  uplinks = [ ];
                  ingressReturn = true;
                };
                name =
                  canonicalP2pLinkNameForEndpointsWithSuffix policyUnit upstreamSelectorUnit
                    "access-${toString access}--uplink-wan";
              }
            ];
        ingressLanes = lib.concatMap ingressLaneForAccess ingressTargetAccessUnits;
      in
      (lib.concatMap downstreamPolicyLane accessUnitNames)
      ++ lanesFromScopes
      ++ ingressLanes;
}
