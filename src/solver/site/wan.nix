{ lib }:

{
  build =
    {
      lib,
      site,
      localPool,

      rolesResult ? null,
      roleFromInput ? (if rolesResult != null then rolesResult.roleFromInput else (_: null)),
      nodesBase ? (site.nodes or site.units or { }),
    }:

    let
      prefix = import ../../../lib/model/prefix-utils.nix { inherit lib; };

      mkConnectedRoute = prefix.mkConnectedRoute;

      normalizeRouteEntry =
        x:
        if builtins.isString x then
          toString x
        else if builtins.isAttrs x && (x.dst or null) != null then
          toString x.dst
        else
          toString x;

      normalizeRouteList =
        xs:
        if xs == null then
          [ ]
        else if builtins.isList xs then
          map normalizeRouteEntry xs
        else
          [ (normalizeRouteEntry xs) ];

      normalizeMaybeString = x: if x == null then null else toString x;

      tenantFromUplink =
        uplink:
        if
          uplink ? ingressSubject
          && uplink.ingressSubject ? kind
          && uplink.ingressSubject.kind == "tenant"
          && uplink.ingressSubject ? name
          && uplink.ingressSubject.name != null
        then
          uplink.ingressSubject.name
        else
          "unclassified";

      hasForwardingAddress = uplink: (uplink.addr4 or null) != null || (uplink.addr6 or null) != null;

      allNodes = builtins.attrNames nodesBase;

      coreUnits = lib.filter (u: (roleFromInput u) == "core") allNodes;

      sortedCoreUnits = lib.sort (a: b: toString a < toString b) coreUnits;

      _haveCore =
        if sortedCoreUnits == [ ] then
          throw "network-forwarding-model: expected at least one node with role='core'"
        else
          true;

      explicitUpstreamCores =
        if site ? upstreams && builtins.isAttrs site.upstreams && site.upstreams ? cores then
          site.upstreams.cores
        else if site ? uplinks && builtins.isAttrs site.uplinks && site.uplinks ? cores then
          site.uplinks.cores
        else
          { };

      nodeLevelUplinksForCore =
        core:
        if
          nodesBase ? "${core}"
          && builtins.isAttrs nodesBase.${core}
          && nodesBase.${core} ? uplinks
          && builtins.isAttrs nodesBase.${core}.uplinks
        then
          nodesBase.${core}.uplinks
        else
          { };

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

      explicitSpecsForCore =
        core:
        if explicitUpstreamCores ? "${core}" then
          normalizeUplinkList explicitUpstreamCores.${core}
        else
          [ ];

      mergeUplinkSpec =
        core: explicit:
        let
          nodeUplinks = nodeLevelUplinksForCore core;
          fromNodeRaw =
            if nodeUplinks ? "${explicit.name}" && builtins.isAttrs nodeUplinks.${explicit.name} then
              nodeUplinks.${explicit.name}
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

      nodeOnlySpecsForCore =
        core:
        let
          nodeUplinks = nodeLevelUplinksForCore core;
          names = lib.sort (a: b: a < b) (builtins.attrNames nodeUplinks);
        in
        map (
          name:
          let
            v = nodeUplinks.${name};
          in
          normalizeUplinkSpec (
            if builtins.isAttrs v then v // { name = toString name; } else { name = toString name; }
          )
        ) names;

      dedupeByName =
        specs:
        builtins.attrValues (builtins.foldl' (acc: spec: acc // { "${spec.name}" = spec; }) { } specs);

      upstreamCoresEffective = lib.listToAttrs (
        map (
          core:
          let
            explicitSpecs = explicitSpecsForCore core;
            explicitNames = map (s: s.name) explicitSpecs;
            mergedExplicit = map (spec: mergeUplinkSpec core spec) explicitSpecs;
            nodeOnly = lib.filter (spec: !(lib.elem spec.name explicitNames)) (nodeOnlySpecsForCore core);
            combined = dedupeByName (mergedExplicit ++ nodeOnly);
          in
          {
            name = core;
            value = lib.sort (a: b: a.name < b.name) combined;
          }
        ) sortedCoreUnits
      );

      uplinkSpecsForCore =
        core: if upstreamCoresEffective ? "${core}" then upstreamCoresEffective.${core} else [ ];

      discoveredUplinkCores = lib.filter (
        core: builtins.length (uplinkSpecsForCore core) > 0
      ) sortedCoreUnits;

      _haveUplinkCore =
        if discoveredUplinkCores == [ ] then
          throw ''
            network-forwarding-model: no uplinks discovered for any core

            expected one of:
            - site.upstreams.cores.<core> = [ "<uplink>" ... ]
            - site.uplinks.cores.<core> = [ { name = "<uplink>"; ... } ... ]
            - site.nodes.<core>.uplinks = { <uplink> = { ... }; ...; }
          ''
        else
          true;

      declaredUplinkNames = lib.sort (a: b: a < b) (
        lib.unique (
          lib.concatMap (
            core: map (uplinkSpec: uplinkSpec.name) (uplinkSpecsForCore core)
          ) discoveredUplinkCores
        )
      );

      forwardingUplinkSpecsForCore = core: lib.filter hasForwardingAddress (uplinkSpecsForCore core);

      uplinkCores = lib.filter (
        core: builtins.length (forwardingUplinkSpecsForCore core) > 0
      ) sortedCoreUnits;

      uplinkNameEntries = lib.concatMap (
        core:
        map (uplinkSpec: {
          name = uplinkSpec.name;
          value = toString core;
        }) (forwardingUplinkSpecsForCore core)
      ) uplinkCores;

      uplinkCoreByName = lib.listToAttrs uplinkNameEntries;

      wanSpecs = lib.concatMap (
        core:
        map (uplinkSpec: {
          core = toString core;
          uplink = uplinkSpec;
        }) (forwardingUplinkSpecsForCore core)
      ) uplinkCores;

      mkPrebuiltWanInterface =
        {
          linkName,
          uplinkName,
          tenant,
          uplink,
        }:
        {
          name = linkName;
          interface = linkName;
          link = linkName;
          kind = "wan";
          type = "wan";
          carrier = "wan";
          uplink = uplinkName;
          upstream = uplinkName;
          overlay = null;

          tenant = tenant;
          gateway = true;

          addr4 = uplink.addr4 or null;
          peerAddr4 = uplink.peerAddr4 or null;
          addr6 = uplink.addr6 or null;
          peerAddr6 = uplink.peerAddr6 or null;
          addr6Public = null;
          ll6 = uplink.ll6 or null;

          uplinkRoutes4 = normalizeRouteList (uplink.ipv4 or [ ]);
          uplinkRoutes6 = normalizeRouteList (uplink.ipv6 or [ ]);

          routes = {
            ipv4 = lib.optional ((uplink.addr4 or null) != null) (mkConnectedRoute uplink.addr4);
            ipv6 = lib.optional ((uplink.addr6 or null) != null) (mkConnectedRoute uplink.addr6);
          };

          ra6Prefixes = [ ];
          acceptRA = false;
          dhcp = false;
        };

      mkWanLink =
        _idx: spec:
        let
          core = spec.core;
          uplink = spec.uplink;
          uplinkName = uplink.name;
          linkName = "wan-${core}-${uplinkName}";
          tenant = tenantFromUplink uplink;

          prebuiltInterfaceData = mkPrebuiltWanInterface {
            inherit
              linkName
              uplinkName
              tenant
              uplink
              ;
          };
        in
        {
          name = linkName;
          value = {
            kind = "wan";
            type = "wan";
            carrier = "wan";
            uplink = uplinkName;
            upstream = uplinkName;
            overlay = null;
            members = [ core ];
            endpoints = {
              "${core}" = {
                node = core;
                interface = linkName;
                uplink = uplinkName;
                gateway = true;
                tenant = tenant;
                addr4 = uplink.addr4 or null;
                peerAddr4 = uplink.peerAddr4 or null;
                addr6 = uplink.addr6 or null;
                peerAddr6 = uplink.peerAddr6 or null;
                ll6 = uplink.ll6 or null;
                uplinkRoutes4 = normalizeRouteList (uplink.ipv4 or [ ]);
                uplinkRoutes6 = normalizeRouteList (uplink.ipv6 or [ ]);
              }
              // {
                interfaceData = prebuiltInterfaceData;
              };
            };
          };
        };

      wanLinks = lib.listToAttrs (lib.imap0 mkWanLink wanSpecs);

      uplinkNames = lib.sort (a: b: a < b) (lib.unique (builtins.attrNames uplinkCoreByName));

    in
    builtins.seq _haveCore (
      builtins.seq _haveUplinkCore {
        coreUnits = sortedCoreUnits;
        uplinkCores = uplinkCores;
        uplinkCoreByName = uplinkCoreByName;
        uplinkNames = uplinkNames;
        declaredUplinkCores = discoveredUplinkCores;
        declaredUplinkNames = declaredUplinkNames;
        wanLinks = wanLinks;
      }
    );
}
