# ./src/solver/site.nix
{ lib }:

{ enterprise
, siteId
, site
}:

let
  utils  = import ../util { inherit lib; };
  derive = import ../util/derive.nix { inherit lib; };

  allocP2P = import ../../lib/p2p/alloc.nix { inherit lib; };
  resolve  = import ../../lib/topology-resolve.nix { inherit lib; };

  _ =
    if builtins.isAttrs site then true
    else throw "network-solver: sites.${enterprise}.${siteId} must be an attrset";

  ordering =
    utils.requireAttr
      "sites.${enterprise}.${siteId}.transit.ordering"
      (site.transit.ordering or null);

  p2pPool =
    utils.requireAttr
      "sites.${enterprise}.${siteId}.addressPools.p2p"
      (site.addressPools.p2p or null);

  attachments = site.attachment or [ ];
  accessUnits = lib.unique (map (a: a.unit) attachments);

  orderedUnits =
    lib.unique
      (lib.concatMap
        (p:
          if builtins.isList p
             && builtins.length p == 2
             && builtins.isString (builtins.elemAt p 0)
             && builtins.isString (builtins.elemAt p 1) then
            [ (builtins.elemAt p 0) (builtins.elemAt p 1) ]
          else
            throw "network-solver: sites.${enterprise}.${siteId}.transit.ordering must contain 2-element string pairs"
        )
        ordering);

  loopUnits =
    if site ? routerLoopbacks then
      builtins.attrNames site.routerLoopbacks
    else
      [ ];

  allUnits = lib.unique (orderedUnits ++ accessUnits ++ loopUnits);

  _unitsOk =
    if allUnits != [ ] then true
    else throw "network-solver: no router units found";

  nodes =
    lib.listToAttrs
      (map
        (n: {
          name = n;
          value =
            (lib.optionalAttrs ((derive.roleForUnit n) != null) {
              role = derive.roleForUnit n;
            }) // { };
        })
        allUnits);

  tenants =
    if site ? domains && site.domains ? tenants && builtins.isList site.domains.tenants then
      site.domains.tenants
    else
      [ ];

  firstTenant =
    if tenants != [ ] then
      builtins.head tenants
    else
      null;

  siteForAlloc =
    {
      siteName = siteId;
      links = ordering;
      linkPairs = ordering;
      p2p-pool = p2pPool;
      inherit nodes;
      domains = site.domains or null;
    };

  p2pLinks = allocP2P.alloc { site = siteForAlloc; };

  compilerIR =
    builtins.removeAttrs site [
      "id"
      "enterprise"
    ];

  topoRaw =
    {
      siteName = siteId;
      inherit nodes;
      links = p2pLinks;
      inherit compilerIR;
    };

  topoResolved = resolve topoRaw;

  cleaned =
    builtins.removeAttrs topoResolved [
      "id"
      "enterprise"
      "siteName"
      "tenantV4Base"
      "ulaPrefix"
    ];

in
cleaned
