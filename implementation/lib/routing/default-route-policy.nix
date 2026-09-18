{ lib, ... }:

let
  pathNodes =
    path:
    lib.unique (
      lib.concatMap
        (
          nodePath:
          if builtins.isList nodePath then map toString nodePath else [ ]
        )
        ((path.nodePathAlternatives or [ ]) ++ [ (path.nodePath or [ ]) ])
    );

  # FS-370/FS-171: a default-exit binding belongs to the path's **source**
  # scope, not to every node that happens to appear in the path. A wildcard
  # (`to = "any"`) path lists several destination-access variants, so matching
  # on membership would attribute one access's exit to another. The originating
  # node is the head of the modeled node path.
  pathOriginatesAt =
    accessName: path:
    let
      heads = map (
        nodePath: if builtins.isList nodePath && nodePath != [ ] then toString (builtins.head nodePath) else null
      ) ((path.nodePathAlternatives or [ ]) ++ [ (path.nodePath or [ ]) ]);
    in
    builtins.elem (toString accessName) heads;

  # FS-322: reachability is a scope property; a permission relation names only
  # what is allowed and never names uplinks. The default-route authority for a
  # selection is therefore derived from the exit scopes the selection resolves
  # to, not from a `destination.uplinks` list on the relation.
  #
  # The compiler's traffic path already carries the resolved exits: the terminal
  # nodes of `nodePathAlternatives` (and `corePathNodes`) are the exit cores the
  # selecting scope may reach. Those cores map back to uplink names through the
  # route facts (`uplinkCoreNamesByUplink`).
  #
  # `destination.uplinks`/`destination.name` are the superseded pre-FS-322 shape
  # (FS-081/FS-984); they are still read here only as a fallback so an already
  # migrated model does not regress, and are otherwise ignored.
  uplinkCoresByIndex =
    routeFacts:
    let
      byUplink = routeFacts.uplinkCoreNamesByUplink or { };
    in
    builtins.foldl'
      (acc: uplinkName: builtins.foldl' (inner: coreName: inner // { ${coreName} = uplinkName; }) acc (byUplink.${uplinkName} or [ ]))
      { }
      (builtins.attrNames byUplink);

  pathExitCoreNames =
    path:
    let
      alternatives = path.nodePathAlternatives or [ ];
      paths = if alternatives != [ ] then alternatives else [ (path.nodePath or [ ]) ];
      terminal =
        nodePath:
        if builtins.isList nodePath && nodePath != [ ] then toString (lib.last nodePath) else null;
      explicit = path.corePathNodes or [ ];
    in
    lib.unique (
      lib.filter (name: name != null) (map terminal paths ++ map toString explicit)
    );

  coreNamesToUplinkNames =
    routeFacts: coreNames:
    let
      byCore = uplinkCoresByIndex routeFacts;
    in
    lib.unique (
      lib.filter (
        uplinkName: uplinkName != null
      ) (map (coreName: byCore.${coreName} or null) coreNames)
    );

  legacyPathDestinationUplinks =
    destination:
    if (destination.kind or null) != "external" then
      [ ]
    else if builtins.isList (destination.uplinks or null) then
      map toString destination.uplinks
    else if (destination.name or null) != null then
      [ (toString destination.name) ]
    else
      [ ];

  # A default exit is only reachable where the permission relation names an
  # external destination (FS-210/FS-322): a path to a tenant or service is not
  # a default. The resolved exit scopes of an external path are its terminal
  # cores (`corePathNodes` / terminal of `nodePathAlternatives`); they map back
  # to the modeled uplink names that carry the default.
  pathDefaultUplinks =
    { routeFacts, path }:
    let
      destination = path.destination or { };
    in
    if (destination.kind or null) != "external" then
      [ ]
    else
      let
        coreUplinks = coreNamesToUplinkNames routeFacts (pathExitCoreNames path);
      in
      if coreUplinks != [ ] then
        coreUplinks
      else
        legacyPathDestinationUplinks destination;

  tenantAccessUnits =
    topo:
    let
      attachments = topo.attachments or [ ];
    in
    builtins.foldl'
      (acc: attachment:
      if (attachment.kind or null) != "tenant" || (attachment.name or null) == null || (attachment.unit or null) == null then
        acc
      else
        let
          tenant = toString attachment.name;
        in
        acc // { "${tenant}" = (acc.${tenant} or [ ]) ++ [ (toString attachment.unit) ]; })
      { }
      attachments;

  relationAccessUnits =
    topo: source:
    let
      byTenant = tenantAccessUnits topo;
    in
    if (source.kind or null) == "tenant" && (source.name or null) != null then
      byTenant.${toString source.name} or [ ]
    else if (source.kind or null) == "tenant-set" && builtins.isList (source.members or null) then
      lib.concatMap (tenant: byTenant.${toString tenant} or [ ]) source.members
    else
      [ ];

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
          (import ./route-context/facts.nix { inherit lib; self = { outPath = ../../..; }; }).build topo;
      scopes = scopeNamesFor topo accessName;
    in
    lib.sort (a: b: a < b) (
      lib.unique (
        lib.concatMap
          (
            path:
            if
              (path.action or null) == "allow"
              && builtins.any (scope: pathOriginatesAt scope path) scopes
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
          (import ./route-context/facts.nix { inherit lib; self = { outPath = ../../..; }; }).build topo;
      scopes = scopeNamesFor topo accessName;
    in
    lib.unique (
      map (path: path.relationId or null) (
        lib.filter
          (
            path:
            (path.action or null) == "allow"
            && builtins.any (scope: pathOriginatesAt scope path) scopes
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
