{ lib }:

let
  normalizeRole =
    role:
    if role == null then
      null
    else
      let
        s = toString role;
      in
      if s == "" then null else s;

  explicitRoleFrom =
    node:
    if builtins.isAttrs node && (node.role or null) != null then normalizeRole node.role else null;

  forwardingFunctionsOf =
    node:
    if builtins.isAttrs node && builtins.isList (node.forwardingFunctions or null) then
      map toString node.forwardingFunctions
    else
      [ ];

  roleFromForwardingFunctions =
    node:
    let
      fns = forwardingFunctionsOf node;
    in
    if
      lib.any (fn: lib.elem fn fns) [
        "access-gateway"
        "tenant-edge"
        "traversal-entry"
      ]
    then
      "access"
    else if lib.elem "policy-enforcer" fns then
      "policy"
    else if lib.elem "downstream-selector" fns then
      "downstream-selector"
    else if
      lib.any (fn: lib.elem fn fns) [
        "upstream-selector"
        "egress-selector"
      ]
    then
      "upstream-selector"
    else if
      lib.any (fn: lib.elem fn fns) [
        "uplink-anchor"
        "external-egress"
      ]
    then
      "core"
    else
      null;

  roleFromForwardingSemantics =
    site: nodeName:
    let
      semantics = site.forwardingSemantics or { };
      nodes = semantics.nodes or { };
      node = nodes.${nodeName} or { };

      policyNodeName = normalizeRole (
        if (site.policyNodeName or null) != null then
          site.policyNodeName
        else
          semantics.policyNodeName or null
      );

      upstreamSelectorNodeName = normalizeRole (
        if (site.upstreamSelectorNodeName or null) != null then
          site.upstreamSelectorNodeName
        else
          semantics.upstreamSelectorNodeName or null
      );

      coreNodeNames = map toString (
        if site ? coreNodeNames && builtins.isList site.coreNodeNames then
          site.coreNodeNames
        else if semantics ? coreNodeNames && builtins.isList semantics.coreNodeNames then
          semantics.coreNodeNames
        else
          [ ]
      );
    in
    if !(builtins.isAttrs semantics) || !(builtins.isAttrs nodes) || !(nodes ? "${nodeName}") then
      null
    else
      let
        explicit = explicitRoleFrom node;
      in
      if explicit != null then
        explicit
      else if policyNodeName != null && nodeName == policyNodeName then
        "policy"
      else if upstreamSelectorNodeName != null && nodeName == upstreamSelectorNodeName then
        "upstream-selector"
      else if lib.elem nodeName coreNodeNames then
        "core"
      else
        roleFromForwardingFunctions node;

in
{
  roleFromSite =
    site: nodeName:
    let
      n = toString nodeName;

      topologyNodes =
        if
          site ? topology
          && builtins.isAttrs site.topology
          && site.topology ? nodes
          && builtins.isAttrs site.topology.nodes
        then
          site.topology.nodes
        else
          { };

      siteNodes = if site ? nodes && builtins.isAttrs site.nodes then site.nodes else { };

      unitNodes = if site ? units && builtins.isAttrs site.units then site.units else { };

      explicit =
        if topologyNodes ? "${n}" then
          explicitRoleFrom topologyNodes.${n}
        else if siteNodes ? "${n}" then
          explicitRoleFrom siteNodes.${n}
        else if unitNodes ? "${n}" then
          explicitRoleFrom unitNodes.${n}
        else
          null;
    in
    if explicit != null then explicit else roleFromForwardingSemantics site n;
}
