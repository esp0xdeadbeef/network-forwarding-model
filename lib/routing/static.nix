{ lib }:

let
  graph = import ./graph.nix { inherit lib; };
  helpers = import ./static-helpers.nix { inherit lib; };

  laneUplinkNameFromLinkName =
    linkName:
    let
      marker = "--uplink-";
      s = toString linkName;
      parts = lib.splitString marker s;
    in
    if builtins.length parts < 2 then null else builtins.elemAt parts ((builtins.length parts) - 1);

  nextHopWithPreferredUplinks =
    {
      topo,
      from,
      to,
      preferredUplinks ? [ ],
    }:
    let
      links = topo.links or { };

      candidates = lib.sort (a: b: a < b) (
        lib.filter (
          lname:
          let
            l = links.${lname};
            members = graph.membersOf l;
          in
          lib.elem from members && lib.elem to members
        ) (builtins.attrNames links)
      );

      preferredSet = lib.unique (map toString (lib.filter (x: x != null) preferredUplinks));

      preferredCandidates =
        if preferredSet == [ ] then
          [ ]
        else
          lib.filter (
            lname:
            let
              uplinkName = laneUplinkNameFromLinkName lname;
            in
            uplinkName != null && builtins.elem uplinkName preferredSet
          ) candidates;

      chosen =
        if preferredCandidates != [ ] then
          builtins.head preferredCandidates
        else if candidates != [ ] then
          builtins.head candidates
        else
          null;

      linkObj = if chosen == null then null else links.${chosen};
      epTo = if linkObj == null then { } else graph.getEp chosen linkObj to;
    in
    {
      linkName = chosen;
      via4 = if epTo ? addr4 && epTo.addr4 != null then helpers.stripMask epTo.addr4 else null;
      via6 = if epTo ? addr6 && epTo.addr6 != null then helpers.stripMask epTo.addr6 else null;
    };

  intentAttr = kind: {
    intent = {
      kind = kind;
    };
  };

  mkRoute4 =
    {
      dst,
      via4 ? null,
      proto,
      intentKind,
      preserveDst ? false,
    }:
    {
      dst = helpers.canonicalCidr dst;
      inherit proto;
    }
    // lib.optionalAttrs (via4 != null) { inherit via4; }
    // intentAttr intentKind
    // lib.optionalAttrs preserveDst { inherit preserveDst; };

  mkRoute6 =
    {
      dst,
      via6 ? null,
      proto,
      intentKind,
      preserveDst ? false,
    }:
    {
      dst = helpers.canonicalCidr dst;
      inherit proto;
    }
    // lib.optionalAttrs (via6 != null) { inherit via6; }
    // intentAttr intentKind
    // lib.optionalAttrs preserveDst { inherit preserveDst; };

  remotePrefixesOfKind =
    topo: nodeName: kind:
    let
      tenantOwnerEntries =
        if kind == "tenant" then builtins.attrValues (topo.tenantPrefixOwners or { }) else [ ];

      overlayEntries =
        if kind == "overlay" then builtins.attrValues (topo.overlayReachability or { }) else [ ];

      perTenantOwner =
        entry:
        if entry.owner == nodeName then
          [ ]
        else
          [
            {
              family = entry.family;
              dst = entry.dst;
              owner = entry.owner;
              kind = "tenant";
            }
          ];

      perOverlayOwner =
        overlay:
        let
          owners = overlay.terminateOn or [ ];

          v4s = map (r: {
            family = 4;
            dst = r.dst or null;
          }) (overlay.routes4 or [ ]);

          v6s = map (r: {
            family = 6;
            dst = r.dst or null;
          }) (overlay.routes6 or [ ]);

          prefixes = lib.filter (e: e.dst != null) (v4s ++ v6s);
        in
        lib.concatMap (
          owner:
          if owner == nodeName then
            [ ]
          else
            map (
              e:
              e
              // {
                owner = owner;
                kind = "overlay";
                overlay = overlay.overlay or null;
                peerSite = overlay.peerSite or null;
              }
            ) prefixes
        ) owners;

      prefixSetFor = otherNode: builtins.attrValues (helpers.prefixSetFromP2pIfaces otherNode);

      perNode =
        other:
        if other == nodeName then
          [ ]
        else
          map (
            x:
            x
            // {
              owner = other;
              kind = "p2p";
            }
          ) (prefixSetFor topo.nodes.${other});

    in
    if kind == "tenant" then
      lib.concatMap perTenantOwner tenantOwnerEntries
    else if kind == "overlay" then
      lib.concatMap perOverlayOwner overlayEntries
    else
      lib.concatMap perNode (helpers.allNodeNames topo);

  resolveRemotePrefix =
    topo: nodeName: dstEntry:
    let
      path = graph.shortestPath {
        links = topo.links or { };
        src = nodeName;
        dst = dstEntry.owner;
      };
    in
    if path == null || builtins.length path < 2 then
      null
    else
      let
        hop = builtins.elemAt path 1;
        preferredUplinks =
          if dstEntry.kind == "overlay" && (dstEntry.overlay or null) != null then
            [ dstEntry.overlay ]
          else if builtins.elem (dstEntry.owner or null) (helpers.uplinkCores topo) then
            topo.uplinkNames or [ ]
          else
            [ ];
        nh = nextHopWithPreferredUplinks {
          inherit topo;
          from = nodeName;
          to = hop;
          inherit preferredUplinks;
        };
      in
      if nh.linkName == null then
        null
      else if dstEntry.family == 4 && nh.via4 == null then
        null
      else if dstEntry.family == 6 && nh.via6 == null then
        null
      else
        dstEntry
        // {
          hopNode = hop;
          linkName = nh.linkName;
          via4 = nh.via4;
          via6 = nh.via6;
        };

  buildRoutesForGroup =
    topo: mode: es:
    let
      sample = builtins.head es;

      rawDsts = map (e: e.dst) es;
      summarizedDsts = helpers.summarizeCidrs sample.family rawDsts;

      intentKind = if sample.kind == "overlay" then "overlay-reachability" else "internal-reachability";

      rawRoutes =
        if sample.family == 4 then
          map (
            dst:
            mkRoute4 {
              inherit dst intentKind;
              via4 = sample.via4;
              proto = "internal";
              preserveDst = sample.kind == "p2p";
            }
          ) summarizedDsts
        else
          map (
            dst:
            mkRoute6 {
              inherit dst intentKind;
              via6 = sample.via6;
              proto = "internal";
              preserveDst = sample.kind == "p2p";
            }
          ) summarizedDsts;

      aggDst =
        if mode == "none" then
          null
        else if sample.kind == "p2p" then
          helpers.buildP2pAggregate topo sample.family
        else if sample.kind == "tenant" then
          helpers.buildTenantAggregate topo sample.family
        else
          null;

      aggRoute =
        if aggDst == null then
          [ ]
        else if sample.family == 4 then
          [
            (mkRoute4 {
              dst = aggDst;
              via4 = sample.via4;
              proto = "internal";
              inherit intentKind;
            })
          ]
        else
          [
            (mkRoute6 {
              dst = aggDst;
              via6 = sample.via6;
              proto = "internal";
              inherit intentKind;
            })
          ];
    in
    {
      linkName = sample.linkName;
      routes4 = if sample.family == 4 then helpers.dedupeRoutes (rawRoutes ++ aggRoute) else [ ];
      routes6 = if sample.family == 6 then helpers.dedupeRoutes (rawRoutes ++ aggRoute) else [ ];
    };

  aggregatePrefixesForNode =
    topo: nodeName:
    let
      mode = helpers.aggregationMode topo;
      node = topo.nodes.${nodeName};
      ownSet = helpers.ownConnectedPrefixes node;

      remote = lib.filter (e: !(ownSet ? "${toString e.family}|${e.dst}")) (
        (remotePrefixesOfKind topo nodeName "p2p")
        ++ (remotePrefixesOfKind topo nodeName "tenant")
        ++ (remotePrefixesOfKind topo nodeName "overlay")
      );

      resolved = lib.filter (x: x != null) (map (resolveRemotePrefix topo nodeName) remote);

      perNextHopKey =
        e:
        "${e.linkName}|${toString e.family}|${toString (e.via4 or "")}|${toString (e.via6 or "")}|${e.kind}|${toString (e.overlay or "")}|${toString (e.peerSite or "")}";

      grouped = builtins.foldl' (
        acc: e: acc // { "${perNextHopKey e}" = (acc.${perNextHopKey e} or [ ]) ++ [ e ]; }
      ) { } resolved;

      perLink = builtins.foldl' (
        acc: g:
        let
          built = buildRoutesForGroup topo mode g;
        in
        acc
        // {
          "${built.linkName}" = {
            routes4 = helpers.dedupeRoutes ((acc.${built.linkName}.routes4 or [ ]) ++ built.routes4);
            routes6 = helpers.dedupeRoutes ((acc.${built.linkName}.routes6 or [ ]) ++ built.routes6);
          };
        }
      ) { } (builtins.attrValues grouped);
    in
    perLink;

  addInternalRoutes =
    topo: nodeName: node:
    let
      perLink = aggregatePrefixesForNode topo nodeName;
      linkNames = builtins.attrNames perLink;
    in
    builtins.foldl' (
      acc: linkName:
      let
        add = perLink.${linkName};
      in
      helpers.addRoutesOnLink acc linkName add.routes4 add.routes6
    ) node linkNames;

  addDirectWanDefaults =
    topo: nodeName: node:
    let
      ifs = node.interfaces or { };
      ifNames = builtins.attrNames ifs;

      step =
        acc: ifName:
        let
          iface = ifs.${ifName};

          add4Prefixes =
            if (iface.peerAddr4 or null) == null then
              [ ]
            else
              map (
                dst:
                mkRoute4 {
                  inherit dst;
                  via4 = helpers.stripMask iface.peerAddr4;
                  proto = "uplink";
                  intentKind = "uplink-learned-reachability";
                }
              ) (iface.uplinkRoutes4 or [ ]);

          add6Prefixes =
            if (iface.peerAddr6 or null) == null then
              [ ]
            else
              map (
                dst:
                mkRoute6 {
                  inherit dst;
                  via6 = helpers.stripMask iface.peerAddr6;
                  proto = "uplink";
                  intentKind = "uplink-learned-reachability";
                }
              ) (iface.uplinkRoutes6 or [ ]);

          add4Default =
            if
              (iface.kind or null) == "wan" && (iface.gateway or false) && (iface.peerAddr4 or null) != null
            then
              [
                (mkRoute4 {
                  dst = helpers.default4;
                  via4 = helpers.stripMask iface.peerAddr4;
                  proto = "default";
                  intentKind = "default-reachability";
                })
              ]
            else if
              (iface.kind or null) == "wan" && (iface.gateway or false) && (iface.addr4 or null) != null
            then
              [
                {
                  dst = helpers.default4;
                  proto = "default";
                  intent = {
                    kind = "default-reachability";
                  };
                }
              ]
            else
              [ ];

          add6Default =
            if
              (iface.kind or null) == "wan" && (iface.gateway or false) && (iface.peerAddr6 or null) != null
            then
              [
                (mkRoute6 {
                  dst = helpers.default6;
                  via6 = helpers.stripMask iface.peerAddr6;
                  proto = "default";
                  intentKind = "default-reachability";
                })
              ]
            else if
              (iface.kind or null) == "wan" && (iface.gateway or false) && (iface.addr6 or null) != null
            then
              [
                {
                  dst = helpers.default6;
                  proto = "default";
                  intent = {
                    kind = "default-reachability";
                  };
                }
              ]
            else
              [ ];

          add4 = add4Prefixes ++ add4Default;
          add6 = add6Prefixes ++ add6Default;
        in
        if add4 == [ ] && add6 == [ ] then acc else helpers.addRoutesOnLink acc ifName add4 add6;
    in
    builtins.foldl' step node ifNames;

  addDefaultTowardNearestUplinkCore =
    topo: nodeName: node:
    let
      uplinks = helpers.uplinkCores topo;
    in
    if uplinks == [ ] || lib.elem nodeName uplinks then
      node
    else
      let
        reachable = lib.filter (
          u:
          let
            p = graph.shortestPath {
              links = topo.links or { };
              src = nodeName;
              dst = u;
            };
          in
          p != null && builtins.length p >= 2
        ) uplinks;

        target = if reachable == [ ] then null else builtins.elemAt (lib.sort (a: b: a < b) reachable) 0;
      in
      if target == null then
        node
      else
        let
          path = graph.shortestPath {
            links = topo.links or { };
            src = nodeName;
            dst = target;
          };
          hop = builtins.elemAt path 1;
          nh = nextHopWithPreferredUplinks {
            inherit topo;
            from = nodeName;
            to = hop;
            preferredUplinks = topo.uplinkNames or [ ];
          };
          add4 =
            if nh.via4 == null then
              [ ]
            else
              [
                (mkRoute4 {
                  dst = helpers.default4;
                  via4 = nh.via4;
                  proto = "default";
                  intentKind = "default-reachability";
                })
              ];
          add6 =
            if nh.via6 == null then
              [ ]
            else
              [
                (mkRoute6 {
                  dst = helpers.default6;
                  via6 = nh.via6;
                  proto = "default";
                  intentKind = "default-reachability";
                })
              ];
        in
        if nh.linkName == null then node else helpers.addRoutesOnLink node nh.linkName add4 add6;

  uplinkRouteEntriesFromNode =
    node:
    let
      ifs = node.interfaces or { };
      ifNames = builtins.attrNames ifs;

      perIface =
        ifName:
        let
          iface = ifs.${ifName};
          rs = helpers.ifaceRoutes iface;
        in
        (map (r: {
          family = 4;
          dst = r.dst or null;
        }) (lib.filter (r: (r.proto or null) == "uplink" && (r ? dst)) rs.ipv4))
        ++ (map (r: {
          family = 6;
          dst = r.dst or null;
        }) (lib.filter (r: (r.proto or null) == "uplink" && (r ? dst)) rs.ipv6));
    in
    lib.concatMap perIface ifNames;

  uplinkLearnedRoutesForSelector =
    topo: nodeName:
    let
      selectorNode = topo.upstreamSelectorNodeName or null;
      uplinkCores = helpers.uplinkCores topo;
      ownNode = topo.nodes.${nodeName};
      ownSet = helpers.ownConnectedPrefixes ownNode;

      advertised = lib.concatMap (
        core:
        let
          node = topo.nodes.${core} or { };
          path = graph.shortestPath {
            links = topo.links or { };
            src = nodeName;
            dst = core;
          };
        in
        if path == null || builtins.length path < 2 then
          [ ]
        else
          let
            hop = builtins.elemAt path 1;
            nh = nextHopWithPreferredUplinks {
              inherit topo;
              from = nodeName;
              to = hop;
              preferredUplinks = topo.uplinkNames or [ ];
            };

            exported = lib.filter (e: e.dst != null && !(ownSet ? "${toString e.family}|${e.dst}")) (
              uplinkRouteEntriesFromNode node
            );
          in
          if nh.linkName == null then
            [ ]
          else
            map (
              e:
              e
              // {
                linkName = nh.linkName;
                via4 = if e.family == 4 then nh.via4 else null;
                via6 = if e.family == 6 then nh.via6 else null;
              }
            ) exported
      ) uplinkCores;

      usable = lib.filter (
        e: (e.family == 4 && e.via4 != null) || (e.family == 6 && e.via6 != null)
      ) advertised;

      perLink = builtins.foldl' (
        acc: e:
        let
          add4 =
            if e.family == 4 then
              [
                (mkRoute4 {
                  dst = e.dst;
                  via4 = e.via4;
                  proto = "uplink";
                  intentKind = "uplink-learned-reachability";
                })
              ]
            else
              [ ];

          add6 =
            if e.family == 6 then
              [
                (mkRoute6 {
                  dst = e.dst;
                  via6 = e.via6;
                  proto = "uplink";
                  intentKind = "uplink-learned-reachability";
                })
              ]
            else
              [ ];
        in
        acc
        // {
          "${e.linkName}" = {
            routes4 = helpers.dedupeRoutes ((acc.${e.linkName}.routes4 or [ ]) ++ add4);
            routes6 = helpers.dedupeRoutes ((acc.${e.linkName}.routes6 or [ ]) ++ add6);
          };
        }
      ) { } usable;
    in
    if selectorNode == null || nodeName != selectorNode then { } else perLink;

  addUplinkLearnedRoutesToSelector =
    topo: nodeName: node:
    let
      perLink = uplinkLearnedRoutesForSelector topo nodeName;
      linkNames = builtins.attrNames perLink;
    in
    builtins.foldl' (
      acc: linkName:
      let
        add = perLink.${linkName};
      in
      helpers.addRoutesOnLink acc linkName add.routes4 add.routes6
    ) node linkNames;

in
{
  attach =
    topo:
    let
      nodes0 = topo.nodes or { };

      nodes1 = lib.mapAttrs (
        n: node:
        let
          n1 = addInternalRoutes topo n node;
          n2 = addDefaultTowardNearestUplinkCore topo n n1;
          n3 = addDirectWanDefaults topo n n2;
        in
        n3
      ) nodes0;

      topo1 = topo // {
        nodes = nodes1;
      };

      nodes2 = lib.mapAttrs (n: node: addUplinkLearnedRoutesToSelector topo1 n node) nodes1;
    in
    topo1 // { nodes = nodes2; };
}
