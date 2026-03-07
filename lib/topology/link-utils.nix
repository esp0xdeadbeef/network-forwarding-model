{ lib }:

let
  membersOf = l: lib.unique ((l.members or [ ]) ++ (builtins.attrNames (l.endpoints or { })));

  endpointsOf = l: l.endpoints or { };

  chooseEndpointKey =
    linkName: l: nodeName:
    let
      eps = endpointsOf l;
      exact = if eps ? "${nodeName}" then nodeName else null;
      byLinkName = "${nodeName}-${linkName}";
      byLink = if eps ? "${byLinkName}" then byLinkName else null;
      bySemanticName =
        let
          nm = l.name or null;
          k = if nm == null then null else "${nodeName}-${nm}";
        in
        if k != null && eps ? "${k}" then k else null;
      pref = "${nodeName}-";
      prefKeys = lib.filter (k: lib.hasPrefix pref k) (builtins.attrNames eps);
      byPrefix = if prefKeys == [ ] then null else lib.head (lib.sort (a: b: a < b) prefKeys);
    in
    if exact != null then
      exact
    else if byLink != null then
      byLink
    else if bySemanticName != null then
      bySemanticName
    else
      byPrefix;

  getEp =
    linkName: l: nodeName:
    let
      k = chooseEndpointKey linkName l nodeName;
      eps = endpointsOf l;
    in
    if k == null then { } else (eps.${k} or { });

  resolveEndpointNodeName =
    {
      linkName,
      link,
      epKey,
      nodeNames,
    }:
    let
      candidates = lib.filter (
        nodeName:
        epKey == nodeName
        || epKey == "${nodeName}-${linkName}"
        || (
          let
            nm = link.name or null;
          in
          nm != null && epKey == "${nodeName}-${nm}"
        )
      ) nodeNames;
    in
    if builtins.length candidates == 1 then
      builtins.elemAt candidates 0
    else if builtins.length candidates == 0 then
      throw "topology-resolve: endpoint '${epKey}' on link '${linkName}' does not reference a valid node"
    else
      throw "topology-resolve: endpoint '${epKey}' on link '${linkName}' is ambiguous across nodes: ${lib.concatStringsSep ", " candidates}";

  resolvedMemberNodes =
    {
      linkName,
      link,
      nodeNames,
    }:
    let
      explicitMembers = link.members or [ ];
      endpointKeys = builtins.attrNames (endpointsOf link);
      resolvedEndpointNodes = map (
        epKey:
        resolveEndpointNodeName {
          inherit
            linkName
            link
            epKey
            nodeNames
            ;
        }
      ) endpointKeys;
    in
    lib.unique (explicitMembers ++ resolvedEndpointNodes);

  getEpStrict =
    {
      linkName,
      link,
      nodeName,
      nodeNames,
    }:
    let
      ep = getEp linkName link nodeName;
      hasKey = (chooseEndpointKey linkName link nodeName) != null;
      isMember = lib.elem nodeName (resolvedMemberNodes {
        inherit linkName link nodeNames;
      });
    in
    if hasKey then
      ep
    else if isMember then
      throw "topology-resolve: missing endpoint for member '${nodeName}' on link '${linkName}'"
    else
      { };
in
{
  inherit
    membersOf
    endpointsOf
    chooseEndpointKey
    getEp
    resolveEndpointNodeName
    resolvedMemberNodes
    getEpStrict
    ;
}
