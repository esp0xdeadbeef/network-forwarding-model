{ lib, self ? { outPath = ./.; }, ... }:

topo:

let
  overlayCoreSelection = import (self.outPath + "/implementation/lib/routing/overlay-core-selection.nix") { inherit lib self; };

  tenantAttachments =
    node:
    lib.filter (tenant: tenant != null) (
      map
        (attachment:
          if (attachment.kind or null) == "tenant" then toString (attachment.name or null) else null)
        (node.attachments or [ ])
    );

  sharesTenantAttachment =
    left: right:
    let
      leftTenants = tenantAttachments left;
      rightTenants = tenantAttachments right;
    in
    builtins.any (tenant: builtins.elem tenant rightTenants) leftTenants;

  nodesForGraph = topo.nodes or { };
  overlayCores = overlayCoreSelection.overlayTerminatingCores topo;

  edgesForCore =
    coreName:
    let
      core = nodesForGraph.${coreName} or { };
      accessNodes = overlayCoreSelection.underlayAccessNodesForCore topo coreName;
    in
    map
      (accessName: [ coreName accessName ])
      (lib.filter
        (accessName:
          builtins.hasAttr accessName nodesForGraph
          && sharesTenantAttachment core nodesForGraph.${accessName})
        accessNodes);
in
lib.unique (lib.concatMap edgesForCore overlayCores)
