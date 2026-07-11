{ lib, self ? { outPath = ./.; }, ... }:

let
  link = import (self.outPath + "/implementation/lib/topology/link-utils.nix") { inherit lib self; };
in
rec {
  inherit link;

  defaultRoutePolicy = import (self.outPath + "/implementation/lib/routing/default-route-policy.nix") { inherit lib; };
  helpers = import (self.outPath + "/implementation/lib/routing/static-helpers.nix") { inherit lib self; };
  routeContext = import (self.outPath + "/implementation/lib/routing/route-context.nix") { inherit lib self; };

  sortedUnique = xs: lib.sort (a: b: toString a < toString b) (lib.unique (map toString xs));
  roleOf = nodes: nodeName: (nodes.${nodeName} or { }).role or null;

  upstreamSelectorFor =
    topo:
    let
      nodes = topo.nodes or { };
      explicit = topo.upstreamSelectorNodeName or null;
      inferred = lib.filter (nodeName: roleOf nodes nodeName == "upstream-selector") (builtins.attrNames nodes);
    in
    if explicit != null then toString explicit else if inferred == [ ] then null else builtins.head (sortedUnique inferred);

  allUpstreamSelectorNames =
    topo:
    let
      nodes = topo.nodes or { };
    in
    sortedUnique (lib.filter (nodeName: roleOf nodes nodeName == "upstream-selector") (builtins.attrNames nodes));

  tenantsForAccess =
    topo: accessName:
    sortedUnique (
      lib.filter (tenant: tenant != null) (
        map
          (
            attachment:
            if
              (attachment.kind or null) == "tenant"
              && (attachment.name or null) != null
              && (attachment.unit or null) != null
              && toString attachment.unit == accessName
            then
              attachment.name
            else
              null
          )
          (topo.attachments or [ ])
      )
    );

  linkUplinkNames =
    linkObj:
    let
      meta = if builtins.isAttrs (linkObj.laneMeta or null) then linkObj.laneMeta else { };
      fromList = if builtins.isList (linkObj.uplinks or null) then linkObj.uplinks else [ ];
      fromMeta =
        if meta.uplink or null != null then [ meta.uplink ]
        else if builtins.isList (meta.uplinks or null) then meta.uplinks
        else [ ];
      fromAttrs =
        lib.optional ((linkObj.uplink or null) != null) linkObj.uplink
        ++ lib.optional ((linkObj.upstream or null) != null) linkObj.upstream;
    in
    sortedUnique (fromList ++ fromMeta ++ fromAttrs);
}
