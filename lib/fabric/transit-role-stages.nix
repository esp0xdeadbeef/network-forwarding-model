{ }:

let
  ranks = {
    access = 0;
    downstream-selector = 1;
    policy = 2;
    upstream-selector = 3;
    core = 4;
  };
in
rec {
  transitRank =
    role:
    let
      roleName = toString role;
    in
    if ranks ? "${roleName}" then
      ranks.${roleName}
    else
      throw "network-forwarding-model: unsupported role in transit ordering: ${roleName}";

  transitRankOrFallback =
    fallback: role:
    let
      roleName = toString role;
    in
    if ranks ? "${roleName}" then ranks.${roleName} else fallback;

  nextTransitRole =
    {
      hasDownstreamSelector,
      hasUpstreamSelector,
      role,
    }:
    if role == "access" then
      if hasDownstreamSelector then "downstream-selector" else "policy"
    else if role == "downstream-selector" then
      "policy"
    else if role == "policy" then
      if hasUpstreamSelector then "upstream-selector" else "core"
    else if role == "upstream-selector" then
      "core"
    else
      null;

  expectedTransitAdjacencies =
    {
      accessNodes,
      coreNodes,
      downstreamNode,
      policyNode,
      upstreamSelectorNode,
    }:
    let
      nodesForRole =
        role:
        if role == "access" then
          accessNodes
        else if role == "downstream-selector" then
          if downstreamNode == null then [ ] else [ downstreamNode ]
        else if role == "policy" then
          if policyNode == null then [ ] else [ policyNode ]
        else if role == "upstream-selector" then
          if upstreamSelectorNode == null then [ ] else [ upstreamSelectorNode ]
        else if role == "core" then
          coreNodes
        else
          [ ];

      rolesWithSources = [
        "access"
        "downstream-selector"
        "policy"
        "upstream-selector"
      ];

      nextRoleFor =
        sourceRole:
        nextTransitRole {
          hasDownstreamSelector = downstreamNode != null;
          hasUpstreamSelector = upstreamSelectorNode != null;
          role = sourceRole;
        };
    in
    builtins.concatMap (
      sourceRole:
      let
        targetRole = nextRoleFor sourceRole;
      in
      builtins.concatMap (
        source:
        map (target: {
          inherit source sourceRole target targetRole;
        }) (nodesForRole targetRole)
      ) (nodesForRole sourceRole)
    ) rolesWithSources;
}
