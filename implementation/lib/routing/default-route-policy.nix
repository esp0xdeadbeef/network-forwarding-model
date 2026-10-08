{ lib, self ? { outPath = ./.; }, ... }:

let
  pathsMod = import ./default-route-policy/paths.nix { inherit lib; };
  paths = pathsMod.make { topo = null; routeFacts = null; };
  inherit (paths)
    pathNodes
    tenantAccessUnits
    pathOriginatesAt
    uplinkCoresByIndex
    pathExitCoreNames
    coreNamesToUplinkNames
    legacyPathDestinationUplinks
    pathDefaultUplinks
    relationAccessUnits
    ;

  relationDefaultUplinksForAccess =
    { topo, routeFacts, accessName }:
    lib.concatMap
      (
        relation:
        if
          (relation.action or null) == "allow"
          && builtins.elem accessName (relationAccessUnits topo (relation.from or { }))
        then
          (
            let
              cores = coreNamesToUplinkNames routeFacts (pathExitCoreNames relation);
            in
            if cores != [ ] then
              cores
            else
              legacyPathDestinationUplinks (relation.to or { })
          )
        else
          [ ]
      )
      ((topo.communicationContract or { }).allowedRelations or [ ]);

  # FS-171/FS-370: a default-exit binding belongs to a **source scope**. A
  # scope name may be a tenant or an access scope; resolve both to the same
  # exit set. The access node is the realization binding that carries the
  # scope's ports, so a scope's selections are the union of the scopes/tenants
  # it serves.
  scopeNamesFor =
    topo: scopeName:
    let
      byTenant = tenantAccessUnits topo;
      name = toString scopeName;
      tenantsOnAccess = builtins.filter (t: builtins.elem name (byTenant.${t} or [ ])) (
        builtins.attrNames byTenant
      );
      accessUnitsForTenant = byTenant.${name} or [ ];
    in
    lib.unique (
      lib.filter (s: s != "") (
        [ name ] ++ tenantsOnAccess ++ accessUnitsForTenant
      )
    );

  anyTrafficDefaultUplinksForAccessFor =
    { topo, routeFacts ? null, accessName }:
    let
      facts =
        if routeFacts != null then
          routeFacts
        else
          (import ./route-context/facts.nix { inherit lib self; }).build topo;
      scopes = scopeNamesFor topo accessName;
    in
    lib.sort (a: b: a < b) (
      lib.unique (
        lib.concatMap
          (
            path:
            if
              (path.action or null) == "allow"
              && builtins.any (scope: pathOriginatesAt topo scope path) scopes
            then
              pathDefaultUplinks { routeFacts = facts; inherit path; }
            else
              [ ]
          )
          (topo.trafficPaths or [ ])
        ++ lib.concatMap (
          scope: relationDefaultUplinksForAccess { inherit topo routeFacts; accessName = scope; }
        ) scopes
      )
    );

  # Public curried entry point (topology, access name) preserved for callers
  # that only hold the topology.
  anyTrafficDefaultUplinksForAccess =
    topo: accessName:
    anyTrafficDefaultUplinksForAccessFor { inherit topo accessName; };

  relationIdsForAccessUplinkFor =
    { topo, routeFacts ? null, accessName, uplinkName }:
    let
      facts =
        if routeFacts != null then
          routeFacts
        else
          (import ./route-context/facts.nix { inherit lib self; }).build topo;
      scopes = scopeNamesFor topo accessName;
    in
    lib.unique (
      map (path: path.relationId or null) (
        lib.filter
          (
            path:
            (path.action or null) == "allow"
            && builtins.any (scope: pathOriginatesAt topo scope path) scopes
            && builtins.elem uplinkName (pathDefaultUplinks {
              inherit path;
              routeFacts = facts;
            })
          )
          (topo.trafficPaths or [ ])
      )
    );

  relationIdsForAccessUplink =
    topo: accessName: uplinkName:
    relationIdsForAccessUplinkFor { inherit topo accessName uplinkName; };

in
{
  inherit
    anyTrafficDefaultUplinksForAccess
    relationIdsForAccessUplink
    ;

  # Backwards-compatible curried wrappers: callers that only have `topo` keep
  # working; the resolver derives route facts from the topology when none are
  # supplied.
  accessMayUseDefault =
    topo: accessName: uplinkName:
    accessName != null
    && uplinkName != null
    && builtins.elem uplinkName (anyTrafficDefaultUplinksForAccess topo accessName);

  returnBehaviorForAccessUplink =
    topo: accessName: uplinkName:
    let
      ids = relationIdsForAccessUplink topo accessName uplinkName;
    in
    if ids == [ ] then null else "symmetric";
}
