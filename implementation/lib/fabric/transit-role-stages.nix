{ lib, ... }:

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
    { hasDownstreamSelector
    , hasUpstreamSelector
    , role
    ,
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

  # Find downstream-selector that a given access node connects to in the topology links
  findConnectedDownstream =
    links: accessNode: downstreamNodes:
    lib.findFirst
      (dsNode:
        lib.any
          (linkName:
            let
              l = links.${linkName};
              members = l.members or [ ];
            in
            (l.kind or null) == "p2p" && lib.elem accessNode members && lib.elem dsNode members
          )
          (builtins.attrNames links)
      )
      null
      downstreamNodes;

  # Find upstream-selector that connects to a given core node
  findConnectedUpstream =
    links: coreNode: upstreamNodes:
    lib.findFirst
      (usNode:
        lib.any
          (linkName:
            let
              l = links.${linkName};
              members = l.members or [ ];
            in
            (l.kind or null) == "p2p" && lib.elem coreNode members && lib.elem usNode members
          )
          (builtins.attrNames links)
      )
      null
      upstreamNodes;

  expectedTransitAdjacencies =
    { accessNodes
    , coreNodes
    , downstreamNodes
    , policyNode
    , upstreamSelectorNodes
    , links
    ,
    }:
    let
      # For each access node, find which downstream-selector it connects to
      accessToDownstream =
        lib.filter
          (adj: adj.target != null)
          (map
            (accessNode:
              let
                ds = findConnectedDownstream links accessNode downstreamNodes;
              in
              if ds != null then {
                source = accessNode;
                sourceRole = "access";
                target = ds;
                targetRole = "downstream-selector";
              } else {
                source = accessNode;
                sourceRole = "access";
                target = null;
                targetRole = "downstream-selector";
              }
            )
            accessNodes);

      # For each downstream-selector, verify it connects to policy
      downstreamToPolicy =
        if policyNode == null then [ ]
        else map
          (dsNode: {
            source = dsNode;
            sourceRole = "downstream-selector";
            target = policyNode;
            targetRole = "policy";
          })
          downstreamNodes;

      # For policy, verify it connects to each upstream-selector
      policyToUpstream =
        if policyNode == null then [ ]
        else map
          (usNode: {
            source = policyNode;
            sourceRole = "policy";
            target = usNode;
            targetRole = "upstream-selector";
          })
          upstreamSelectorNodes;

      # For each upstream-selector, find which core it connects to
      upstreamToCore =
        lib.concatMap
          (usNode:
            let
              connectedCores = lib.filter
                (coreNode: findConnectedUpstream links coreNode [ usNode ] != null)
                coreNodes;
            in
            map
              (coreNode: {
                source = usNode;
                sourceRole = "upstream-selector";
                target = coreNode;
                targetRole = "core";
              })
              connectedCores
          )
          upstreamSelectorNodes;
    in
    accessToDownstream ++ downstreamToPolicy ++ policyToUpstream ++ upstreamToCore;
}
