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

  _ =
    if builtins.isAttrs site then
      true
    else
      throw "network-solver: sites.${enterprise}.${siteId} must be an attrset";

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

  ordering = utils.requireAttr "sites.${enterprise}.${siteId}.transit.ordering" (
    site.transit.ordering or null
  );
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
        throw "network-solver: transit.ordering must contain 2-element pairs"
    ) ordering
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
      ordering
      accessUnits
      allUnits
      ;
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
  topoResult = topoMod.build {
    inherit
      lib
      site
      siteId
      enterprise
      ordering
      p2pPool
      rolesResult
      wanResult
      enforcementResult
      sites
      ;
  };
in
builtins.seq rolesResult.assertions topoResult
