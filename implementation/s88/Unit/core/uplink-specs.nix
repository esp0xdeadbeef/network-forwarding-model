{ lib, self ? { outPath = ./.; }, ... }:

let
  routes = import (self.outPath + "/implementation/lib/model/routes.nix") { inherit lib self; };

  normalizeRouteList = routes.normalizeRouteDestinationList;

  normalizeMaybeString = x: if x == null then null else toString x;

  normalizeUplinkSpec =
    u:
    if builtins.isString u then
      {
        name = toString u;
        ipv4 = [ ];
        ipv6 = [ ];
        addr4 = null;
        peerAddr4 = null;
        addr6 = null;
        peerAddr6 = null;
        ll6 = null;
      }
    else if builtins.isAttrs u && u ? name then
      u
      // {
        name = toString u.name;
        ipv4 = normalizeRouteList (u.ipv4 or [ ]);
        ipv6 = normalizeRouteList (u.ipv6 or [ ]);
        addr4 = normalizeMaybeString (u.addr4 or null);
        peerAddr4 = normalizeMaybeString (u.peerAddr4 or null);
        addr6 = normalizeMaybeString (u.addr6 or null);
        peerAddr6 = normalizeMaybeString (u.peerAddr6 or null);
        ll6 = normalizeMaybeString (u.ll6 or null);
      }
    else
      null;

  normalizeUplinkList =
    xs:
    let
      specs = lib.filter (x: x != null) (map normalizeUplinkSpec xs);
    in
    lib.sort (a: b: a.name < b.name) specs;

  dedupeByName =
    specs:
    builtins.attrValues (builtins.foldl' (acc: spec: acc // { "${spec.name}" = spec; }) { } specs);

in
{
  inherit normalizeRouteList;

  explicitInputs =
    site:
    if site ? upstreams && builtins.isAttrs site.upstreams && site.upstreams ? cores then
      site.upstreams.cores
    else if site ? uplinks && builtins.isAttrs site.uplinks && site.uplinks ? cores then
      site.uplinks.cores
    else
      { };

  nodeInputs =
    nodesBase: unitName:
    if
      nodesBase ? "${unitName}"
      && builtins.isAttrs nodesBase.${unitName}
      && nodesBase.${unitName} ? uplinks
      && builtins.isAttrs nodesBase.${unitName}.uplinks
    then
      nodesBase.${unitName}.uplinks
    else
      { };

  mergeForUnit =
    { explicitInputs
    , nodeInputs
    , unitName
    ,
    }:
    let
      explicitSpecs =
        if explicitInputs ? "${unitName}" then normalizeUplinkList explicitInputs.${unitName} else [ ];

      explicitNames = map (s: s.name) explicitSpecs;

      mergeExplicit =
        explicit:
        let
          fromNodeRaw =
            if nodeInputs ? "${explicit.name}" && builtins.isAttrs nodeInputs.${explicit.name} then
              nodeInputs.${explicit.name}
            else
              { };

          fromNode = normalizeUplinkSpec (fromNodeRaw // { name = explicit.name; });
        in
        fromNode
        // explicit
        // {
          name = explicit.name;
          ipv4 = normalizeRouteList ((fromNode.ipv4 or [ ]) ++ (explicit.ipv4 or [ ]));
          ipv6 = normalizeRouteList ((fromNode.ipv6 or [ ]) ++ (explicit.ipv6 or [ ]));
          addr4 = if (explicit.addr4 or null) != null then explicit.addr4 else (fromNode.addr4 or null);
          peerAddr4 =
            if (explicit.peerAddr4 or null) != null then explicit.peerAddr4 else (fromNode.peerAddr4 or null);
          addr6 = if (explicit.addr6 or null) != null then explicit.addr6 else (fromNode.addr6 or null);
          peerAddr6 =
            if (explicit.peerAddr6 or null) != null then explicit.peerAddr6 else (fromNode.peerAddr6 or null);
          ll6 = if (explicit.ll6 or null) != null then explicit.ll6 else (fromNode.ll6 or null);
        };

      nodeOnly =
        map
          (
            name:
            let
              v = nodeInputs.${name};
            in
            normalizeUplinkSpec (
              if builtins.isAttrs v then v // { name = toString name; } else { name = toString name; }
            )
          )
          (lib.sort (a: b: a < b) (builtins.attrNames nodeInputs));
    in
    lib.sort (a: b: a.name < b.name) (
      dedupeByName ((map mergeExplicit explicitSpecs) ++ (lib.filter (spec: !(lib.elem spec.name explicitNames)) nodeOnly))
    );
}
