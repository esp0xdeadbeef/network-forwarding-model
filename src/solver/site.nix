{ lib }:
{ enterprise, siteId, site }:

let
  utils    = import ../util { inherit lib; };
  rolesMod = import ./site/roles.nix { inherit lib; };
  wanMod   = import ./site/wan.nix { inherit lib; };
  topoMod  = import ./site/topology { inherit lib; };
  enfMod   = import ./site/enforcement.nix { inherit lib; };

  _ = if builtins.isAttrs site then true else
        throw "network-solver: sites.${enterprise}.${siteId} must be an attrset";

  ordering  = utils.requireAttr "sites.${enterprise}.${siteId}.transit.ordering" (site.transit.ordering or null);
  p2pPool   = utils.requireAttr "sites.${enterprise}.${siteId}.addressPools.p2p" (site.addressPools.p2p or null);
  localPool = utils.requireAttr "sites.${enterprise}.${siteId}.addressPools.local" (site.addressPools.local or null);

  attachments = site.attachment or [ ];
  accessUnits = lib.unique (map (a: a.unit) attachments);

  orderedUnits =
    lib.unique (lib.concatMap
      (p:
        if builtins.isList p && builtins.length p == 2 then p
        else throw "network-solver: transit.ordering must contain 2-element pairs")
      ordering);

  loopUnits = if site ? routerLoopbacks then builtins.attrNames site.routerLoopbacks else [ ];
  allUnits  = lib.unique (orderedUnits ++ accessUnits ++ loopUnits);

  rolesResult =
    rolesMod.compute {
      inherit lib site enterprise siteId ordering accessUnits allUnits;
    };

  wanResult =
    wanMod.build {
      inherit lib site localPool;
      rolesResult = rolesResult;
      roleFromInput = rolesResult.roleFromInput;
      nodesBase = site.units or site.nodes or { };
    };

  enforcementResult =
    enfMod.build {
      inherit lib site rolesResult wanResult;
    };

  topoResult =
    topoMod.build {
      inherit lib site siteId enterprise ordering p2pPool rolesResult wanResult enforcementResult;
    };

in
  builtins.seq rolesResult.assertions topoResult
