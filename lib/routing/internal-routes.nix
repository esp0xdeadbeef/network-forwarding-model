{ lib }:

let
  graph = import ./graph.nix { inherit lib; };
  helpers = import ./static-helpers.nix { inherit lib; };
in
{
  apply =
    {
      topo,
      nodeName,
      node,
      nextHopWithPreferredUplinks,
      laneUplinkNameFromLinkName,
      loopbackOwnerNodeForDst,
      mkRoute4,
      mkRoute6,
    }:
    let
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
        preferredAccessNodes = lib.unique (
          lib.filter (x: x != null) [
            (dstEntry.owner or null)
            (loopbackOwnerNodeForDst topo dstEntry.family dstEntry.dst)
          ]
        );
        baseNh = nextHopWithPreferredUplinks {
          inherit topo;
          from = nodeName;
          to = hop;
          inherit preferredUplinks;
          inherit preferredAccessNodes;
        };
        candidateLinks =
          let
            links = topo.links or { };
            candidates = lib.sort (a: b: a < b) (
              lib.filter (
                lname:
                let
                  l = links.${lname};
                  members = graph.membersOf l;
                in
                lib.elem nodeName members && lib.elem hop members
              ) (builtins.attrNames links)
            );
            preferredCandidates =
              if preferredUplinks == [ ] then
                [ ]
              else
                lib.filter (
                  lname:
                  let
                    uplinkName = laneUplinkNameFromLinkName lname;
                  in
                  uplinkName != null && builtins.elem uplinkName preferredUplinks
                ) candidates;
          in
          if dstEntry.kind == "overlay" && preferredCandidates != [ ] then
            preferredCandidates
          else if baseNh.linkName == null then
            [ ]
          else
            [ baseNh.linkName ];
        nhs = builtins.map (
          linkName:
          let
            linkObj = (topo.links or { }).${linkName};
            epTo = graph.getEp linkName linkObj hop;
          in
          {
            inherit linkName;
            via4 = if epTo ? addr4 && epTo.addr4 != null then helpers.stripMask epTo.addr4 else null;
            via6 = if epTo ? addr6 && epTo.addr6 != null then helpers.stripMask epTo.addr6 else null;
          }
        ) candidateLinks;
      in
      builtins.filter (entry: entry != null) (
        builtins.map (
          nh:
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
            }
        ) nhs
      );

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

      resolved = builtins.concatLists (map (resolveRemotePrefix topo nodeName) remote);

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
    in
    addInternalRoutes topo nodeName node;
}
