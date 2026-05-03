{ lib }:

let
  graph = import ./graph.nix { inherit lib; };
  helpers = import ./static-helpers.nix { inherit lib; };
  externalIngressUplinkDefaults = import ./external-ingress-uplink-defaults.nix { inherit lib; };
  internalRoutes = import ./internal-routes.nix { inherit lib; };
  defaultRoutes = import ./default-routes.nix { inherit lib; };
  laneUplinkNameFromLinkName =
    linkName:
    let
      marker = "--uplink-";
      s = toString linkName;
      parts = lib.splitString marker s;
    in
    if builtins.length parts < 2 then null else builtins.elemAt parts ((builtins.length parts) - 1);

  laneAccessNodeNameFromLinkName =
    linkName:
    let
      marker = "--access-";
      s = toString linkName;
      parts = lib.splitString marker s;
      lastPart =
        if builtins.length parts < 2 then null else builtins.elemAt parts ((builtins.length parts) - 1);
      segments = if lastPart == null then [ ] else lib.splitString "--uplink-" lastPart;
    in
    if segments == [ ] then null else builtins.elemAt segments 0;

  loopbackOwnerNodeForDst =
    topo: family: dst:
    let
      wanted = helpers.stripMask dst;
      nodes = topo.nodes or { };
      names = builtins.attrNames nodes;
      matches = lib.filter (
        nodeName:
        let
          node = nodes.${nodeName};
          loopback = node.loopback or { };
          raw = if family == 4 then loopback.ipv4 or null else loopback.ipv6 or null;
        in
        raw != null && helpers.stripMask raw == wanted
      ) names;
    in
    if matches == [ ] then null else builtins.head matches;

  nextHopWithPreferredUplinks =
    {
      topo,
      from,
      to,
      preferredUplinks ? [ ],
      preferredAccessNodes ? [ ],
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
      preferredAccessSet = lib.unique (map toString (lib.filter (x: x != null) preferredAccessNodes));

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

      preferredAccessCandidates =
        if preferredAccessSet == [ ] then
          [ ]
        else
          lib.filter (
            lname:
            let
              accessNodeName = laneAccessNodeNameFromLinkName lname;
            in
            accessNodeName != null && builtins.elem accessNodeName preferredAccessSet
          ) candidates;

      chosen =
        if preferredCandidates != [ ] && preferredAccessCandidates != [ ] then
          let
            overlap = lib.filter (lname: builtins.elem lname preferredAccessCandidates) preferredCandidates;
          in
          if overlap != [ ] then builtins.head overlap else builtins.head preferredCandidates
        else if preferredCandidates != [ ] then
          builtins.head preferredCandidates
        else if preferredAccessCandidates != [ ] then
          builtins.head preferredAccessCandidates
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


  addInternalRoutes =
    topo: nodeName: node:
    internalRoutes.apply {
      inherit
        topo
        nodeName
        node
        nextHopWithPreferredUplinks
        laneUplinkNameFromLinkName
        loopbackOwnerNodeForDst
        mkRoute4
        mkRoute6
        ;
    };


  routeDefaultsForNode =
    topo: nodeName: node:
    defaultRoutes.apply {
      inherit
        topo
        nodeName
        node
        nextHopWithPreferredUplinks
        laneAccessNodeNameFromLinkName
        mkRoute4
        mkRoute6
        ;
    };

  addExternalIngressUplinkDefaults =
    topo: nodeName: node:
    externalIngressUplinkDefaults.apply {
      inherit
        topo
        nodeName
        node
        nextHopWithPreferredUplinks
        mkRoute4
        mkRoute6
        ;
    };

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
          withInternalRoutes = addInternalRoutes topo n node;

          nearestUplinkDefaults = routeDefaultsForNode topo n withInternalRoutes;
          withNearestUplinkDefault = nearestUplinkDefaults.addDefaultTowardNearestUplinkCore;

          policyLaneDefaults = routeDefaultsForNode topo n withNearestUplinkDefault;
          withPolicyLaneDefaults = policyLaneDefaults.addDownstreamSelectorPolicyLaneDefaults;

          withExternalIngressDefaults = addExternalIngressUplinkDefaults topo n withPolicyLaneDefaults;

          directWanDefaults = routeDefaultsForNode topo n withExternalIngressDefaults;
        in
        directWanDefaults.addDirectWanDefaults
      ) nodes0;

      topo1 = topo // {
        nodes = nodes1;
      };

      nodes2 = lib.mapAttrs (n: node: addUplinkLearnedRoutesToSelector topo1 n node) nodes1;
    in
    topo1 // { nodes = nodes2; };
}
