{ lib }:

let
  graph = import ./graph.nix { inherit lib; };
  helpers = import ./static-helpers.nix { inherit lib; };

  laneUplinkNameFromLinkName =
    linkName:
    let
      parts = lib.splitString "--uplink-" (toString linkName);
    in
    if builtins.length parts < 2 then null else builtins.elemAt parts ((builtins.length parts) - 1);

  laneAccessNodeNameFromLinkName =
    linkName:
    let
      parts = lib.splitString "--access-" (toString linkName);
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
      matches = lib.filter (
        nodeName:
        let
          loopback = nodes.${nodeName}.loopback or { };
          raw = if family == 4 then loopback.ipv4 or null else loopback.ipv6 or null;
        in
        raw != null && helpers.stripMask raw == wanted
      ) (builtins.attrNames nodes);
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
          linkName:
          let
            members = graph.membersOf links.${linkName};
          in
          lib.elem from members && lib.elem to members
        ) (builtins.attrNames links)
      );

      preferredUplinkSet = lib.unique (map toString (lib.filter (x: x != null) preferredUplinks));
      preferredAccessSet = lib.unique (map toString (lib.filter (x: x != null) preferredAccessNodes));

      preferredUplinkCandidates =
        if preferredUplinkSet == [ ] then
          [ ]
        else
          lib.filter (
            linkName:
            let
              uplinkName = laneUplinkNameFromLinkName linkName;
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
              accessNodeName = laneAccessNodeNameFromLinkName linkName;
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
    laneAccessNodeNameFromLinkName
    laneUplinkNameFromLinkName
    loopbackOwnerNodeForDst
    nextHopWithPreferredUplinks
    ;

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
}
