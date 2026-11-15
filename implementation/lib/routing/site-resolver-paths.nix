{ lib, ... }:

# Site-level resolver path, computed by the forwarding model from the DNS
# relationships and the canonical staged topology. This is forwarding-model
# authority: the resolver path is forwarding structure, not compiler intent.
# The compiler carries requesterScope + upstreamResolver; a supplied
# resolverPath is rejected at the compiler input boundary.
#
# FS-540 / FS-260: a resolver path between two resolver services traverses the
# canonical staged fabric and includes the policy point (access ->
# downstream-selector -> policy -> downstream-selector -> access for
# access<->access; access -> downstream-selector -> policy -> upstream-selector
# -> core for access->core). It is derived from the two endpoint nodes and the
# topology; it is never authored.
#
# The path is published as `resolverPaths` on the site, analogous to `routing`
# (site-routing.nix), so the control-plane model consumes the derived structure
# instead of inventing it.

let
  attrsOrEmpty = a: if builtins.isAttrs a then a else { };
  listOrEmpty = v: if builtins.isList v then v else [ ];

  ranks = {
    access = 0;
    downstream-selector = 1;
    policy = 2;
    upstream-selector = 3;
    core = 4;
  };
  rankOf = role: ranks.${toString role} or null;

  roleOf =
    nodes: name:
    let
      node = attrsOrEmpty (nodes.${name} or null);
    in
      node.role or null;

  firstRoleNode =
    nodes: role:
    let
      matches = builtins.filter (n: roleOf nodes n == role) (builtins.attrNames nodes);
    in
    if matches == [ ] then null else builtins.head matches;

  # The canonical staged path between two endpoint nodes, walking the fabric
  # roles. access<->access crosses the policy point in both directions.
  canonicalStagesBetween =
    { fromRole, toRole }:
    let
      from = rankOf fromRole;
      to = rankOf toRole;
    in
    if from == null || to == null then
      [ ]
    else if from == 0 && to == 0 then
    # access <-> access: out through downstream + policy, back through
    # downstream to the target access.
      [
        "access"
        "downstream-selector"
        "policy"
        "downstream-selector"
        "access"
      ]
    else if from < to then
    # forward direction (towards core).
      [
        "access"
        "downstream-selector"
        "policy"
        "upstream-selector"
        "core"
      ]
    else
    # reverse direction (from core towards access).
      [
        "core"
        "upstream-selector"
        "policy"
        "downstream-selector"
        "access"
      ];

  # Resolve a service name to its provider node using ownership.endpoints
  # (endpoint -> tenant) and the topology attachments (tenant -> node).
  serviceNode = import ./site-resolver-paths/service-node.nix { inherit lib; };
  inherit (serviceNode) nodeForService;

  # Build one resolver path record from a DNS relationship.
  resolverPathFor =
    site: relationship:
    let
      requesterService = toString ((attrsOrEmpty relationship.requester or { }).service or "");
      authorityService = toString ((attrsOrEmpty relationship.authority or { }).service or "");
      requesterNode = nodeForService site requesterService;
      authorityNode = nodeForService site authorityService;
      nodes = attrsOrEmpty (site.nodes or { });
      fromRole = if requesterNode == null then null else roleOf nodes requesterNode;
      toRole = if authorityNode == null then null else roleOf nodes authorityNode;
      stages = canonicalStagesBetween { inherit fromRole toRole; };
      namespace = relationship.namespace or null;
    in
    if requesterNode == null || authorityNode == null || stages == [ ] then
      null
    else
      {
        requesterService = requesterService;
        authorityService = authorityService;
        relationId = (attrsOrEmpty (relationship.relation or { })).id or null;
        requesterNode = requesterNode;
        authorityNode = authorityNode;
        inherit namespace;
        # The canonical stage roles crossed, policy included by construction.
        pathStages = stages;
        # Concrete node names, one per stage role crossed. The first stage role
        # is the requester endpoint, the last is the authority endpoint; the
        # middle roles resolve to their fabric nodes in the topology.
        pathNodes =
          let
            roleNodeForStage =
              idx: role:
              if idx == 0 then
                requesterNode
              else if idx == (builtins.length stages - 1) then
                authorityNode
              else
                firstRoleNode nodes role;
          in
          builtins.filter (n: n != null) (lib.imap0 roleNodeForStage stages);
        policyPoint = firstRoleNode nodes "policy";
      };

  resolverPaths =
    site:
    let
      dns = attrsOrEmpty (site.dns or { });
      localSharing =
        if builtins.isList (dns.localSharingRelations or null) then
          dns.localSharingRelations
        else if builtins.isAttrs (dns.localSharing or null) then
          [ dns.localSharing ]
        else
          [ ];
      built = builtins.filter (r: r != null) (map (rel: resolverPathFor site rel) localSharing);
    in
    built;

in
{
  inherit resolverPaths;
}
