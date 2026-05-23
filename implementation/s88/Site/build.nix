{ lib, self ? { outPath = ./.; }, ... }:
{ enterprise
, siteId
, site
, sites ? { }
,
}:

let
  trace = import (self.outPath + "/lib/trace.nix") { };
  utils = import (self.outPath + "/implementation/lib/s88-support") { inherit lib self; };
  rolesMod = import (self.outPath + "/s88/Unit/roles/build.nix") { inherit lib self; };
  wanMod = import (self.outPath + "/s88/Unit/core.nix") { inherit lib self; };
  topoMod = import ./topology { inherit lib self; };
  enfMod = import (self.outPath + "/s88/ControlModule/enforcement/build.nix") { inherit lib self; };
  transitMod = import ./topology/transit.nix { inherit lib self; };
  transitOrderingMod = import ./transit-ordering.nix { inherit lib self; };
  inputRoleMod = import (self.outPath + "/s88/Unit/roles/input-role.nix") { inherit lib self; };

  _ =
    if builtins.isAttrs site then
      true
    else
      throw "network-forwarding-model: sites.${enterprise}.${siteId} must be an attrset";

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

  siteUnits = if site ? units && builtins.isAttrs site.units then site.units else { };

  forwardingSemanticsNodes =
    if
      site ? forwardingSemantics
      && builtins.isAttrs site.forwardingSemantics
      && site.forwardingSemantics ? nodes
      && builtins.isAttrs site.forwardingSemantics.nodes
    then
      site.forwardingSemantics.nodes
    else
      { };

  nodesBase = forwardingSemanticsNodes // topologyNodes // siteNodes // siteUnits;

  roleFromInputExplicit = inputRoleMod.roleFromSite site;

  rawOrdering = utils.requireAttr "sites.${enterprise}.${siteId}.transit.ordering" (
    site.transit.ordering or null
  );

  rawOrderingPairs =
    trace.emit "site:${enterprise}.${siteId}:normalize-ordering" (
      (transitMod.normalizeInputOrdering {
        siteName = "${enterprise}.${siteId}";
        ordering = rawOrdering;
      }).pairs
    );

  overlayItems =
    let
      overlays = ((site.transport or { }).overlays or [ ]);
    in
    if builtins.isList overlays then
      lib.filter (ov: ov != null && builtins.isAttrs ov) overlays
    else if builtins.isAttrs overlays then
      lib.mapAttrsToList (name: ov: ov // { inherit name; }) overlays
    else
      [ ];

  overlayAttachmentItems =
    let
      attachments = site.overlayAttachments or { };
    in
    if builtins.isAttrs attachments then builtins.attrValues attachments else [ ];

  attachmentsForNode =
    nodeName:
    (nodesBase.${nodeName}.attachments or [ ])
    ++ lib.filter (att: toString (att.unit or "") == nodeName) (site.attachments or [ ]);

  nodeHasTenant =
    nodeName: tenantName:
    lib.any
      (
        attachment:
        (attachment.kind or null) == "tenant"
        && toString (attachment.name or "") == toString tenantName
      )
      (attachmentsForNode nodeName);

  isOverlayUnderlayPair =
    pair:
    let
      a = toString (builtins.elemAt pair 0);
      b = toString (builtins.elemAt pair 1);
      roleA = roleFromInputExplicit a;
      roleB = roleFromInputExplicit b;
      core = if roleA == "core" && roleB == "access" then a else if roleB == "core" && roleA == "access" then b else null;
      access = if roleA == "access" && roleB == "core" then a else if roleB == "access" && roleA == "core" then b else null;
    in
    core != null
    && access != null
    && (
      lib.any
        (
          overlay:
          (overlay.terminateOn or null) == core
          && (overlay.underlayAccess.kind or null) == "tenant"
          && nodeHasTenant access (overlay.underlayAccess.name or "")
        )
        overlayItems
      || lib.any
        (
          attachment:
          builtins.elem core (map toString (attachment.terminatesOn or [ ]))
          && builtins.elem access (map toString (attachment.accessNodes or [ ]))
        )
        overlayAttachmentItems
    );

  canonicalOrderingPairs = lib.filter (pair: !(isOverlayUnderlayPair pair)) rawOrderingPairs;

  canonicalOrdering = trace.emit "site:${enterprise}.${siteId}:canonical-ordering" (transitOrderingMod.canonicalize {
    siteName = "${enterprise}.${siteId}";
    inherit site;
    pairs = canonicalOrderingPairs;
    roleFromInput = roleFromInputExplicit;
  });

  p2pPool = utils.requireAttr "sites.${enterprise}.${siteId}.addressPools.p2p" (
    site.addressPools.p2p or null
  );
  localPool = utils.requireAttr "sites.${enterprise}.${siteId}.addressPools.local" (
    site.addressPools.local or null
  );

  accessUnits = lib.unique (
    lib.filter (x: x != null && x != "") (map utils.unitRefOfAttachment (utils.attachmentsOf site))
  );

  orderedUnits = lib.unique (
    lib.concatMap
      (
        p:
        if builtins.isList p && builtins.length p == 2 then
          p
        else
          throw "network-forwarding-model: transit.ordering must contain 2-element pairs"
      )
      rawOrderingPairs
  );

  allUnits = lib.unique (
    orderedUnits
    ++ accessUnits
    ++ builtins.attrNames (site.routerLoopbacks or { })
    ++ builtins.attrNames topologyNodes
    ++ builtins.attrNames siteNodes
    ++ builtins.attrNames siteUnits
    ++ builtins.attrNames forwardingSemanticsNodes
  );

  rolesResult = trace.emit "site:${enterprise}.${siteId}:roles" (rolesMod.compute {
    inherit
      lib
      site
      enterprise
      siteId
      accessUnits
      allUnits
      ;
    ordering = canonicalOrdering;
  });
  wanResult = trace.emit "site:${enterprise}.${siteId}:wan" (wanMod.build {
    inherit
      lib
      site
      localPool
      rolesResult
      ;
    roleFromInput = rolesResult.roleFromInput;
    inherit nodesBase;
  });
  enforcementResult = trace.emit "site:${enterprise}.${siteId}:enforcement" (enfMod.build {
    inherit
      lib
      site
      rolesResult
      wanResult
      ;
  });
  topologyResult = trace.emit "site:${enterprise}.${siteId}:topology" (topoMod.build {
    inherit
      lib
      site
      siteId
      enterprise
      p2pPool
      rolesResult
      wanResult
      enforcementResult
      sites
      ;
    ordering = canonicalOrdering;
    linkPairs = rawOrderingPairs;
  });
in
builtins.seq rolesResult.assertions topologyResult
