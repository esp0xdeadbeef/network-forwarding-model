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
in
{
  inherit anyTrafficDefaultUplinksForAccess;

  accessMayUseDefault =
    topo: accessName: uplinkName:
    accessName != null
    && uplinkName != null
    && builtins.elem uplinkName (anyTrafficDefaultUplinksForAccess topo accessName);
}
