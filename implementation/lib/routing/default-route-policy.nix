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

  pathDestinationUplinks =
    destination:
    if (destination.kind or null) != "external" then
      [ ]
    else if builtins.isList (destination.uplinks or null) then
      map toString destination.uplinks
    else if (destination.name or null) != null then
      [ (toString destination.name) ]
    else
      [ ];

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
    topo: accessName:
    lib.concatMap
      (
        relation:
        if
          (relation.action or null) == "allow"
          && builtins.elem accessName (relationAccessUnits topo (relation.from or { }))
        then
          pathDestinationUplinks (relation.to or { })
        else
          [ ]
      )
      ((topo.communicationContract or { }).allowedRelations or [ ]);

  anyTrafficDefaultUplinksForAccess =
    topo: accessName:
    lib.sort (a: b: a < b) (
      lib.unique (
        lib.concatMap
          (
            path:
            if
              (path.action or null) == "allow"
              && builtins.elem accessName (pathNodes path)
            then
              pathDestinationUplinks (path.destination or { })
            else
              [ ]
          )
          (topo.trafficPaths or [ ])
        ++ relationDefaultUplinksForAccess topo accessName
      )
    );

  relationIdsForAccessUplink =
    topo: accessName: uplinkName:
    let
      pathDestinationUplinks' =
        destination:
        if (destination.kind or null) != "external" then
          [ ]
        else if builtins.isList (destination.uplinks or null) then
          map toString destination.uplinks
        else if (destination.name or null) != null then
          [ (toString destination.name) ]
        else
          [ ];
    in
    lib.unique (
      map (path: path.relationId or null) (
        lib.filter
          (path:
            (path.action or null) == "allow"
            && builtins.elem accessName (pathNodes path)
            && builtins.elem uplinkName (pathDestinationUplinks' (path.destination or { }))
          )
          (topo.trafficPaths or [ ])
      )
    );

  matchingRelationsForAccessUplink =
    topo: accessName: uplinkName:
    let
      ids = relationIdsForAccessUplink topo accessName uplinkName;
      rels = (topo.communicationContract or { }).allowedRelations or [ ];
    in
    builtins.filter
      (rel: builtins.elem (rel.id or null) ids)
      rels;

in
{
  inherit anyTrafficDefaultUplinksForAccess relationIdsForAccessUplink;

  accessMayUseDefault =
    topo: accessName: uplinkName:
    accessName != null
    && uplinkName != null
    && builtins.elem uplinkName (anyTrafficDefaultUplinksForAccess topo accessName);

  returnBehaviorForAccessUplink =
    topo: accessName: uplinkName:
    let
      matching = matchingRelationsForAccessUplink topo accessName uplinkName;
      hasSymmetricRel = builtins.any
        (rel:
          (rel ? returnBehavior && rel.returnBehavior == "symmetric")
          || (rel ? bidirectional && rel.bidirectional))
        matching;
    in
    if hasSymmetricRel then "symmetric" else null;
}
