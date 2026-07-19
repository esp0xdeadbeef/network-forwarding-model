{ lib }:

{ site
, nodes
, siteExternalDomains
, siteUplinkCoreNames
, siteUplinkNames
, upstreamSelectorNodeName
, maybeOne
, sortedUnique
,
}:

let
  communicationContract = site.communicationContract or { };
  contractRelations =
    if builtins.isList (communicationContract.allowedRelations or null) then
      communicationContract.allowedRelations
    else if builtins.isList (communicationContract.relations or null) then
      communicationContract.relations
    else
      [ ];
  egressRelations = lib.filter
    (
      relation:
      builtins.isAttrs relation
      && (relation.action or null) == "allow"
      && builtins.isAttrs (relation.to or null)
      && (relation.to.kind or null) == "external"
    )
    contractRelations;
  egressRelationIds = sortedUnique (map (relation: relation.id or "") egressRelations);
  egressRelationUplinks = relation:
    let
      destination = relation.to or { };
    in
    if builtins.isList (destination.uplinks or null) then
      sortedUnique destination.uplinks
    else
      [ ];
  hasUnscopedEgressRelation = builtins.any
    (relation: egressRelationUplinks relation == [ ])
    egressRelations;
  explicitlyAuthorizedUplinks = sortedUnique (
    builtins.concatMap egressRelationUplinks egressRelations
  );
  authorizedUplinkNames =
    if egressRelations == [ ] then
      [ ]
    else if hasUnscopedEgressRelation then
      siteUplinkNames
    else
      lib.filter (name: builtins.elem name explicitlyAuthorizedUplinks) siteUplinkNames;
  nodeDeclaredUplinks = nodeName:
    let
      node = nodes.${nodeName} or { };
    in
    if builtins.isAttrs (node.uplinks or null) then
      builtins.attrNames node.uplinks
    else
      [ ];
  authorizedUplinkCoreNames =
    if egressRelations == [ ] then
      [ ]
    else if hasUnscopedEgressRelation then
      siteUplinkCoreNames
    else
      lib.filter
        (
          nodeName:
          builtins.any
            (uplink: builtins.elem uplink authorizedUplinkNames)
            (nodeDeclaredUplinks nodeName)
        )
        siteUplinkCoreNames;
in
{
  inherit authorizedUplinkCoreNames authorizedUplinkNames;
  siteEgressIntent = {
    authorityRelationIds = egressRelationIds;
    enabled = egressRelations != [ ];
    eligibleNodeNames = sortedUnique (
      authorizedUplinkCoreNames
      ++ (if egressRelations == [ ] then [ ] else maybeOne upstreamSelectorNodeName)
    );
    exitNodeNames = sortedUnique authorizedUplinkCoreNames;
    explicit = true;
    externalDomains = if egressRelations == [ ] then [ ] else siteExternalDomains;
    uplinkCoreNodeNames = sortedUnique authorizedUplinkCoreNames;
    uplinkNames = authorizedUplinkNames;
    upstreamSelectorNodeName = if egressRelations == [ ] then null else upstreamSelectorNodeName;
  };
}
