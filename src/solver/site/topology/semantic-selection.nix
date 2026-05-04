{ lib }:

let
  sortedUnique =
    xs:
    lib.sort (a: b: toString a < toString b) (lib.unique (map toString (lib.filter (x: x != null) xs)));

  firstByRole =
    names: roleOf: wanted:
    let
      matches = lib.filter (name: roleOf name == wanted) names;
    in
    if matches == [ ] then null else builtins.head matches;

  namesFromWan =
    wanResult: declaredName: fallbackName:
    if
      wanResult != null
      && wanResult ? "${declaredName}"
      && builtins.isList wanResult.${declaredName}
    then
      sortedUnique wanResult.${declaredName}
    else if
      wanResult != null
      && wanResult ? "${fallbackName}"
      && builtins.isList wanResult.${fallbackName}
    then
      sortedUnique wanResult.${fallbackName}
    else
      [ ];

  externalDomainNamesFromSite =
    site:
    let
      externals =
        if
          site ? domains
          && builtins.isAttrs site.domains
          && site.domains ? externals
          && builtins.isList site.domains.externals
        then
          site.domains.externals
        else
          [ ];
    in
    sortedUnique (
      map (
        external:
        if builtins.isAttrs external && external ? name && external.name != null then
          external.name
        else
          toString external
      ) externals
    );

  roleOfFor =
    {
      nodes,
      rolesResult ? null,
    }:
    let
      roleFromInput =
        if rolesResult != null && rolesResult ? roleFromInput then rolesResult.roleFromInput else (_: null);
    in
    nodeName:
    let
      fromNode =
        if nodes ? "${nodeName}" && builtins.isAttrs nodes.${nodeName} then
          nodes.${nodeName}.role or null
        else
          null;

      fromInput = roleFromInput nodeName;
    in
    if fromNode != null then
      toString fromNode
    else if fromInput != null then
      toString fromInput
    else
      null;

  coreNodeNamesFor =
    {
      site,
      nodeNames,
      roleOf,
    }:
    if site ? coreNodeNames && builtins.isList site.coreNodeNames && site.coreNodeNames != [ ] then
      sortedUnique site.coreNodeNames
    else
      sortedUnique (lib.filter (name: roleOf name == "core") nodeNames);

  policyNodeNameFor =
    {
      site,
      nodeNames,
      roleOf,
    }:
    if site ? policyNodeName && site.policyNodeName != null then
      toString site.policyNodeName
    else
      firstByRole nodeNames roleOf "policy";

  upstreamSelectorNodeNameFor =
    {
      site,
      nodeNames,
      roleOf,
    }:
    if site ? upstreamSelectorNodeName && site.upstreamSelectorNodeName != null then
      toString site.upstreamSelectorNodeName
    else
      firstByRole nodeNames roleOf "upstream-selector";

  siteUplinkCoreNamesFor =
    {
      site,
      wanResult ? null,
    }:
    if site ? uplinkCoreNames && builtins.isList site.uplinkCoreNames then
      sortedUnique site.uplinkCoreNames
    else
      namesFromWan wanResult "declaredUplinkCores" "uplinkCores";

  siteUplinkNamesFor =
    {
      site,
      wanResult ? null,
      siteExternalDomains,
    }:
    let
      fromSite =
        if site ? uplinkNames && builtins.isList site.uplinkNames then
          sortedUnique site.uplinkNames
        else
          [ ];

      fromWan = namesFromWan wanResult "declaredUplinkNames" "uplinkNames";
    in
    if fromWan != [ ] then
      fromWan
    else if fromSite != [ ] then
      fromSite
    else
      siteExternalDomains;

in
{
  inherit
    coreNodeNamesFor
    externalDomainNamesFromSite
    policyNodeNameFor
    roleOfFor
    siteUplinkCoreNamesFor
    siteUplinkNamesFor
    sortedUnique
    upstreamSelectorNodeNameFor
    ;

  maybeOne = x: if x == null then [ ] else [ (toString x) ];
}
