{ lib }:
{
  enterprise,
  siteId,
  site,
  sites ? { },
}:

let
  utils = import ../util { inherit lib; };
  rolesMod = import ./site/roles.nix { inherit lib; };
  wanMod = import ./site/wan.nix { inherit lib; };
  topoMod = import ./site/topology { inherit lib; };
  enfMod = import ./site/enforcement.nix { inherit lib; };
  transitMod = import ./site/topology/transit.nix { inherit lib; };
  transitOrderingMod = import ./site/transit-ordering.nix { inherit lib; };

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

  nodesBase = topologyNodes // siteNodes // siteUnits;

  roleFromInputExplicit =
    node:
    let
      n = toString node;
    in
    if topologyNodes ? "${n}" then
      topologyNodes.${n}.role or null
    else if siteNodes ? "${n}" then
      siteNodes.${n}.role or null
    else if siteUnits ? "${n}" then
      siteUnits.${n}.role or null
    else
      null;

  rawOrdering = utils.requireAttr "sites.${enterprise}.${siteId}.transit.ordering" (
    site.transit.ordering or null
  );

  rawOrderingPairs =
    (transitMod.normalizeInputOrdering {
      siteName = "${enterprise}.${siteId}";
      ordering = rawOrdering;
    }).pairs;

  canonicalOrdering = transitOrderingMod.canonicalize {
    siteName = "${enterprise}.${siteId}";
    pairs = rawOrderingPairs;
    roleFromInput = roleFromInputExplicit;
  };

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
    lib.concatMap (
      p:
      if builtins.isList p && builtins.length p == 2 then
        p
      else
        throw "network-forwarding-model: transit.ordering must contain 2-element pairs"
    ) rawOrderingPairs
  );

  allUnits = lib.unique (
    orderedUnits
    ++ accessUnits
    ++ builtins.attrNames (site.routerLoopbacks or { })
    ++ builtins.attrNames topologyNodes
    ++ builtins.attrNames siteNodes
    ++ builtins.attrNames siteUnits
  );

  rolesResult = rolesMod.compute {
    inherit
      lib
      site
      enterprise
      siteId
      accessUnits
      allUnits
      ;
    ordering = canonicalOrdering;
  };
  wanResult = wanMod.build {
    inherit
      lib
      site
      localPool
      rolesResult
      ;
    roleFromInput = rolesResult.roleFromInput;
    inherit nodesBase;
  };
  enforcementResult = enfMod.build {
    inherit
      lib
      site
      rolesResult
      wanResult
      ;
  };
  topologyResult = topoMod.build {
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
  };
in
builtins.seq rolesResult.assertions topologyResult
