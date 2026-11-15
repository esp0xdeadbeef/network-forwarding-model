{
  lib,
  topo,
  nodeName,
  routeScope,
  dstEntry,
  graphHop,
}:

# Canonical staged next hop for a scoped route.
#
# The policy point in the declared resolver path is the only direction marker
# needed: the canonical model is access/core <-> up/downstream-selector <->
# policy, so a node before that point routes upward on the requester lane, the
# policy point itself routes downward on the destination owner's lane, and a
# node after it is already served by the unscoped route on the destination
# lane. No stage ranking is derived here.
let
  scoped = routeScope != null && (routeScope.access or null) != null;

  firstIndexOf =
    value: xs:
    let
      matches = builtins.filter (i: builtins.elemAt xs i == value) (
        builtins.genList (i: i) (builtins.length xs)
      );
    in
    if matches == [ ] then null else builtins.head matches;

  roleOf = name: (topo.nodes.${name} or { }).role or null;

  scopedPath =
    if scoped && (routeScope.nodePaths or [ ]) != [ ] then
      lib.findFirst (p: builtins.elem nodeName p) null routeScope.nodePaths
    else
      null;

  pathHops =
    if scopedPath == null then
      [ ]
    else
      let
        idx = firstIndexOf nodeName scopedPath;
        next =
          if idx == null || builtins.length scopedPath <= idx + 1 then
            null
          else
            builtins.elemAt scopedPath (idx + 1);
      in
      if next == null then [ ] else [ next ];

  policyNode =
    if !scoped then
      null
    else if (routeScope.policyNode or null) != null then
      routeScope.policyNode
    else
      lib.findFirst (n: roleOf n == "policy") null (if scopedPath == null then [ ] else scopedPath);

  nodeIndex = if scopedPath == null then null else firstIndexOf nodeName scopedPath;
  policyIndex =
    if scopedPath == null || policyNode == null then null else firstIndexOf policyNode scopedPath;

  laneHint =
    if !scoped then
      null
    else if nodeIndex == null || policyIndex == null then
      routeScope.access or null
    else if nodeIndex < policyIndex then
      routeScope.access or null
    else if nodeIndex == policyIndex then
      dstEntry.owner or null
    else
      null;
in
{
  inherit
    scoped
    laneHint
    ;
  hop = if pathHops == [ ] then graphHop else builtins.head pathHops;
}
