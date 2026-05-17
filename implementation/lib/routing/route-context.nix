{ lib, self ? { outPath = ./.; }, ... }:

let
  graph = import ./graph.nix { inherit lib self; };
  helpers = import ./static-helpers.nix { inherit lib self; };

  laneMetaForLink = link:
    if builtins.isAttrs (link.laneMeta or null) then link.laneMeta else { };

  laneUplinkNameFromLink = link: (laneMetaForLink link).uplink or null;

  laneAccessNodeNameFromLink = link: (laneMetaForLink link).access or null;

  loopbackOwnerNodeForDst =
    topo: family: dst:
    loopbackOwnerNodeForDstWithFacts (buildFacts topo) family dst;

  loopbackOwnerNodeForDstWithFacts =
    facts: family: dst:
    let
      wanted = helpers.stripMask dst;
      key = "${toString family}|${wanted}";
    in
    facts.loopbackOwnerByKey.${key} or null;

  buildFacts =
    topo:
    let
      nodes = topo.nodes or { };
      loopbackEntries = lib.concatMap (
        nodeName:
        let
          loopback = nodes.${nodeName}.loopback or { };
          entry =
            family: raw:
            if raw == null then
              [ ]
            else
              [
                {
                  name = "${toString family}|${helpers.stripMask raw}";
                  value = nodeName;
                }
              ];
        in
        (entry 4 (loopback.ipv4 or null)) ++ (entry 6 (loopback.ipv6 or null))
      ) (builtins.attrNames nodes);

      overlayReachabilityNames = builtins.attrNames (topo.overlayReachability or { });
      linkOverlayNames = lib.filter (name: name != null) (
        map (linkName: (topo.links.${linkName}.overlay or null)) (builtins.attrNames (topo.links or { }))
      );
      overlayUplinkNameSet = lib.listToAttrs (
        map (name: {
          inherit name;
          value = true;
        }) (lib.unique (overlayReachabilityNames ++ linkOverlayNames))
      );
      nonOverlayUplinkNames =
        lib.filter (uplinkName: !(builtins.hasAttr uplinkName overlayUplinkNameSet)) (topo.uplinkNames or [ ]);
    in
    {
      loopbackOwnerByKey = builtins.listToAttrs loopbackEntries;
      uplinkCores = helpers.uplinkCores topo;
      inherit overlayUplinkNameSet nonOverlayUplinkNames;
      defaultReachabilityUplinkNames =
        if nonOverlayUplinkNames != [ ] then nonOverlayUplinkNames else topo.uplinkNames or [ ];
    };

  nextHopWithPreferredUplinks =
    {
      topo,
      from,
      to,
      preferredUplinks ? [ ],
      preferredAccessNodes ? [ ],
      routeGraph ? graph.context (topo.links or { }),
    }:
    let
      links = topo.links or { };

      candidates = routeGraph.linksBetween from to;

      preferredUplinkSet = lib.unique (map toString (lib.filter (x: x != null) preferredUplinks));
      preferredAccessSet = lib.unique (map toString (lib.filter (x: x != null) preferredAccessNodes));

      preferredUplinkCandidates =
        if preferredUplinkSet == [ ] then
          [ ]
        else
          lib.filter (
            linkName:
            let
              uplinkName = laneUplinkNameFromLink links.${linkName};
            in
            uplinkName != null && builtins.elem uplinkName preferredUplinkSet
          ) candidates;

      preferredAccessCandidates =
        if preferredAccessSet == [ ] then
          [ ]
        else
          lib.filter (
            linkName:
            let
              accessNodeName = laneAccessNodeNameFromLink links.${linkName};
            in
            accessNodeName != null && builtins.elem accessNodeName preferredAccessSet
          ) candidates;

      chosen =
        if preferredUplinkCandidates != [ ] && preferredAccessCandidates != [ ] then
          let
            overlap = lib.filter (
              linkName: builtins.elem linkName preferredAccessCandidates
            ) preferredUplinkCandidates;
          in
          if overlap != [ ] then builtins.head overlap else builtins.head preferredUplinkCandidates
        else if preferredUplinkCandidates != [ ] then
          builtins.head preferredUplinkCandidates
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

in
{
  inherit
    buildFacts
    laneAccessNodeNameFromLink
    laneUplinkNameFromLink
    loopbackOwnerNodeForDst
    loopbackOwnerNodeForDstWithFacts
    nextHopWithPreferredUplinks
    ;

  mkRoute4 =
    {
      dst,
      via4 ? null,
      proto,
      intentKind,
      metric ? null,
      lane ? null,
      policyOnly ? false,
      reason ? null,
      preserveDst ? false,
    }:
    {
      dst = if dst == helpers.default6 then helpers.default6 else helpers.canonicalCidr dst;
      inherit proto;
    }
    // lib.optionalAttrs (via4 != null) { inherit via4; }
    // lib.optionalAttrs (metric != null) { inherit metric; }
    // lib.optionalAttrs (lane != null) { inherit lane; }
    // lib.optionalAttrs policyOnly { inherit policyOnly; }
    // lib.optionalAttrs (reason != null) { inherit reason; }
    // intentAttr intentKind
    // lib.optionalAttrs preserveDst { inherit preserveDst; };

  mkRoute6 =
    {
      dst,
      via6 ? null,
      proto,
      intentKind,
      metric ? null,
      lane ? null,
      policyOnly ? false,
      reason ? null,
      preserveDst ? false,
    }:
    {
      dst = if dst == helpers.default6 then helpers.default6 else helpers.canonicalCidr dst;
      inherit proto;
    }
    // lib.optionalAttrs (via6 != null) { inherit via6; }
    // lib.optionalAttrs (metric != null) { inherit metric; }
    // lib.optionalAttrs (lane != null) { inherit lane; }
    // lib.optionalAttrs policyOnly { inherit policyOnly; }
    // lib.optionalAttrs (reason != null) { inherit reason; }
    // intentAttr intentKind
    // lib.optionalAttrs (preserveDst || dst == helpers.default6) { preserveDst = true; };
}
