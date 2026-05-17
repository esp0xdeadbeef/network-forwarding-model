{ lib, ... }:

let
  asList =
    value:
    if value == null then [ ] else if builtins.isList value then value else [ value ];

  cleanNodeName =
    value:
    let
      name = toString value;
    in
    if lib.hasPrefix "overlay:" name then null else name;

  cleanNodeNames =
    value:
    if builtins.isList value then
      lib.concatMap cleanNodeNames value
    else
      lib.filter (name: name != null) [ (cleanNodeName value) ];

  addUnique = acc: name: value:
    acc // { "${name}" = lib.unique ((acc.${name} or [ ]) ++ [ value ]); };

  tenantOwnerNodesByName =
    tenantOwnerEntries:
    builtins.foldl' (
      acc: entry:
      let
        tenantName = entry.netName or null;
        owner = entry.owner or null;
      in
      if tenantName == null || owner == null then
        acc
      else
        addUnique acc (toString tenantName) (toString owner)
    ) { } tenantOwnerEntries;

  sourceOwnerNodes =
    ownersByTenant: source:
    let
      kind = source.kind or null;
    in
    if kind == "tenant" then
      ownersByTenant.${toString (source.name or "")} or [ ]
    else if kind == "tenant-set" then
      lib.unique (
        lib.concatMap (
          tenantName: ownersByTenant.${toString tenantName} or [ ]
        ) (asList (source.members or [ ]))
      )
    else
      [ ];

  destinationOverlayNames =
    overlayNames: destination:
    if (destination.kind or null) != "external" then
      [ ]
    else
      let
        byName =
          if (destination.name or null) == null then
            [ ]
          else
            [ (toString destination.name) ];
        byUplink = map toString (asList (destination.uplinks or [ ]));
        requested = lib.unique (byName ++ byUplink);
      in
      lib.filter (overlayName: builtins.elem overlayName overlayNames) requested;

  trafficPathNodes =
    ownersByTenant: path:
    lib.unique (
      (cleanNodeNames (path.corePathNodes or [ ]))
      ++ (cleanNodeNames (path.nodePath or [ ]))
      ++ (cleanNodeNames (path.nodePathAlternatives or [ ]))
      ++ (sourceOwnerNodes ownersByTenant (path.source or { }))
    );

  policyAllowedNodes =
    {
      overlayNames,
      tenantOwnerEntries,
      trafficPaths,
    }:
    let
      ownersByTenant = tenantOwnerNodesByName tenantOwnerEntries;
    in
    builtins.foldl' (
      acc: path:
      if !(builtins.isAttrs path) || (path.action or "allow") != "allow" then
        acc
      else
        let
          overlays = destinationOverlayNames overlayNames (path.destination or { });
          nodesForPath = trafficPathNodes ownersByTenant path;
        in
        builtins.foldl' (
          overlayAcc: overlayName:
          overlayAcc // {
            "${overlayName}" = lib.unique ((overlayAcc.${overlayName} or [ ]) ++ nodesForPath);
          }
        ) acc overlays
    ) { } trafficPaths;

  attachmentAllowedNodes =
    overlayAttachments:
    lib.mapAttrs (
      _overlayName: attachment:
      lib.unique (
        (cleanNodeNames (attachment.accessNodes or [ ]))
        ++ (cleanNodeNames (attachment.canonicalPath or [ ]))
        ++ (cleanNodeNames (attachment.terminateOn or [ ]))
        ++ (cleanNodeNames (attachment.terminatesOn or [ ]))
        ++ (cleanNodeNames (attachment.terminatedOn or [ ]))
      )
    ) overlayAttachments;
in
{
  build =
    topo: tenantOwnerEntries:
    {
      policyAllowedNodes = policyAllowedNodes {
        overlayNames = builtins.attrNames (topo.overlayReachability or { });
        inherit tenantOwnerEntries;
        trafficPaths = topo.trafficPaths or [ ];
      };
      attachmentAllowedNodes = attachmentAllowedNodes (topo.overlayAttachments or { });
    };
}
