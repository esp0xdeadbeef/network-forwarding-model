{ lib }:

{
  build =
    {
      lib,
      site,
      localPool,

      rolesResult ? null,
      roleFromInput ? (if rolesResult != null then rolesResult.roleFromInput else (_: null)),
      nodesBase ? (site.units or site.nodes or { }),
    }:

    let
      addr = import ../../../lib/model/addressing.nix { inherit lib; };

      stripMask =
        cidr:
        let
          parts = lib.splitString "/" (toString cidr);
        in
        if builtins.length parts == 0 then toString cidr else builtins.elemAt parts 0;

      tenantFromUplink =
        uplink:
        if uplink ? ingressSubject
           && uplink.ingressSubject ? kind
           && uplink.ingressSubject.kind == "tenant"
           && uplink.ingressSubject ? name
           && uplink.ingressSubject.name != null
        then uplink.ingressSubject.name
        else "unclassified";

      allUnits = builtins.attrNames nodesBase;

      coreUnits = lib.filter (u: (roleFromInput u) == "core") allUnits;

      sortedCoreUnits = lib.sort (a: b: toString a < toString b) coreUnits;

      _haveCore =
        if sortedCoreUnits == [ ] then
          throw "network-solver: expected at least one unit with role='core'"
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
        if nodesBase ? "${core}"
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
          { name = u; }
        else if builtins.isAttrs u && u ? name then
          u // { name = toString u.name; }
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
          fromNode =
            if nodeUplinks ? "${explicit.name}" && builtins.isAttrs nodeUplinks.${explicit.name} then
              nodeUplinks.${explicit.name}
            else
              { };
        in
        fromNode // explicit // { name = explicit.name; };

      nodeOnlySpecsForCore =
        core:
        let
          nodeUplinks = nodeLevelUplinksForCore core;
          names = lib.sort (a: b: a < b) (builtins.attrNames nodeUplinks);
        in
        map
          (name:
            let
              v = nodeUplinks.${name};
            in
            if builtins.isAttrs v then
              v // { name = toString name; }
            else
              { name = toString name; })
          names;

      dedupeByName =
        specs:
        builtins.attrValues
          (builtins.foldl'
            (acc: spec: acc // { "${spec.name}" = spec; })
            { }
            specs);

      upstreamCoresEffective =
        lib.listToAttrs (
          map
            (core:
              let
                explicitSpecs = explicitSpecsForCore core;
                explicitNames = map (s: s.name) explicitSpecs;
                mergedExplicit = map (spec: mergeUplinkSpec core spec) explicitSpecs;
                nodeOnly =
                  lib.filter (spec: !(lib.elem spec.name explicitNames)) (nodeOnlySpecsForCore core);
                combined = dedupeByName (mergedExplicit ++ nodeOnly);
              in
              {
                name = core;
                value = lib.sort (a: b: a.name < b.name) combined;
              })
            sortedCoreUnits
        );

      uplinkSpecsForCore =
        core:
        if upstreamCoresEffective ? "${core}" then
          upstreamCoresEffective.${core}
        else
          [ ];

      uplinkCores =
        lib.filter (core: builtins.length (uplinkSpecsForCore core) > 0) sortedCoreUnits;

      _haveUplinkCore =
        if uplinkCores == [ ] then
          throw ''
            network-solver: no uplinks discovered for any core

            expected one of:
            - site.upstreams.cores.<core> = [ "<uplink>" ... ]
            - site.uplinks.cores.<core> = [ { name = "<uplink>"; ... } ... ]
            - site.nodes.<core>.uplinks = { <uplink> = { ... }; ...; }
            - site.units.<core>.uplinks = { <uplink> = { ... }; ...; }
          ''
        else
          true;

      uplinkNameEntries =
        lib.concatMap
          (core:
            map
              (uplinkSpec: {
                name = uplinkSpec.name;
                value = toString core;
              })
              (uplinkSpecsForCore core))
          uplinkCores;

      uplinkCoreByName = lib.listToAttrs uplinkNameEntries;

      mkWanNetBase =
        idx:
        100 + (4 * idx);

      mkWanAddr4 =
        hostIndex:
        let
          base = "${stripMask localPool.ipv4}/30";
        in
        addr.hostCidr hostIndex base;

      mkWanAddr6 =
        hostIndex:
        let
          base = "${stripMask localPool.ipv6}/126";
        in
        addr.hostCidr hostIndex base;

      mkWanLL6 =
        hostIndex:
        addr.hostCidr (hostIndex + 1) "fe80::/128";

      wanSpecs =
        lib.concatMap
          (core:
            map
              (uplinkSpec: {
                core = toString core;
                uplink = uplinkSpec;
              })
              (uplinkSpecsForCore core))
          uplinkCores;

      mkWanLink =
        idx: spec:
        let
          base = mkWanNetBase idx;
          hCore = base + 1;
          core = spec.core;
          uplink = spec.uplink;
          uplinkName = uplink.name;
          linkName = "wan-${core}-${uplinkName}";
          tenant = tenantFromUplink uplink;
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
                export = true;
                tenant = tenant;
                addr4 = if localPool ? ipv4 then mkWanAddr4 hCore else null;
                addr6 = if localPool ? ipv6 then mkWanAddr6 hCore else null;
                ll6 = mkWanLL6 hCore;
              };
            };
          };
        };

      wanLinks = lib.listToAttrs (lib.imap0 mkWanLink wanSpecs);

      uplinkNames =
        lib.sort (a: b: a < b) (lib.unique (builtins.attrNames uplinkCoreByName));

    in
    builtins.seq _haveCore (builtins.seq _haveUplinkCore {
      coreUnits = sortedCoreUnits;
      uplinkCores = uplinkCores;
      uplinkCoreByName = uplinkCoreByName;
      uplinkNames = uplinkNames;
      wanLinks = wanLinks;
    });
}
