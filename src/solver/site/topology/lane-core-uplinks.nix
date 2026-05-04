{ lib }:

{
  derive =
    {
      site,
      wanResult,
      upstreamSelectorUnit,
      canonicalP2pLinkNameForEndpoints,
    }:
    let
      linkSpecEndpointA =
        pair:
        if builtins.isList pair then toString (builtins.elemAt pair 0) else toString pair.a;

      linkSpecEndpointB =
        pair:
        if builtins.isList pair then toString (builtins.elemAt pair 1) else toString pair.b;

      linkSpecConnectsEndpoints =
        expectedEndpointA: expectedEndpointB: linkSpec:
        let
          actualEndpointA = linkSpecEndpointA linkSpec;
          actualEndpointB = linkSpecEndpointB linkSpec;
        in
        (actualEndpointA == expectedEndpointA && actualEndpointB == expectedEndpointB)
        || (actualEndpointA == expectedEndpointB && actualEndpointB == expectedEndpointA);

      uplinkNamesForCore =
        coreName:
        let
          wanResultNames =
            lib.filter (
              uplinkName: toString (wanResult.uplinkCoreByName.${uplinkName} or "") == coreName
            ) (builtins.attrNames (wanResult.uplinkCoreByName or { }));
          nodeUplinkNames =
            if builtins.isAttrs (site.nodes.${coreName}.uplinks or null) then
              builtins.attrNames site.nodes.${coreName}.uplinks
            else if builtins.isAttrs (site.topology.nodes.${coreName}.uplinks or null) then
              builtins.attrNames site.topology.nodes.${coreName}.uplinks
            else
              [ ];
        in
        lib.sort builtins.lessThan (lib.unique (wanResultNames ++ nodeUplinkNames));

      endpointOppositeSelector =
        pair:
        let
          a = linkSpecEndpointA pair;
          b = linkSpecEndpointB pair;
        in
        if upstreamSelectorUnit == null then
          null
        else if a == upstreamSelectorUnit then
          b
        else if b == upstreamSelectorUnit then
          a
        else
          null;

      annotateCoreUplinkLane =
        pair:
        let
          a = linkSpecEndpointA pair;
          b = linkSpecEndpointB pair;
          other = endpointOppositeSelector pair;
          uplinkNames = if other == null then [ ] else uplinkNamesForCore other;
        in
        if builtins.length uplinkNames == 1 then
          {
            inherit a b;
            name = canonicalP2pLinkNameForEndpoints a b;
            lane = "uplink::${builtins.head uplinkNames}";
          }
        else
          pair;

      nodePairForLink =
        link:
        if builtins.isList (link.members or null) && builtins.length link.members == 2 then
          {
            a = toString (builtins.elemAt link.members 0);
            b = toString (builtins.elemAt link.members 1);
          }
        else if builtins.isAttrs (link.endpoints or null) && builtins.length (builtins.attrNames link.endpoints) == 2 then
          let
            names = builtins.attrNames link.endpoints;
          in
          {
            a = toString (builtins.elemAt names 0);
            b = toString (builtins.elemAt names 1);
          }
        else
          null;

      coreUplinksForNodePair =
        pair:
        let
          other = if pair == null then null else endpointOppositeSelector pair;
        in
        if other == null then [ ] else uplinkNamesForCore other;

      coreUplinkLaneForNodePair =
        pair:
        let
          uplinks = coreUplinksForNodePair pair;
        in
        if builtins.length uplinks == 1 then "uplink::${builtins.head uplinks}" else null;

      annotateMergedLinkLane =
        _: link:
        let
          existingLane = link.lane or null;
          pair = nodePairForLink link;
          lane = coreUplinkLaneForNodePair pair;
          uplinks = coreUplinksForNodePair pair;
        in
        if (link.kind or null) != "p2p" || uplinks == [ ] then
          link
        else
          link
          // { inherit uplinks; }
          // lib.optionalAttrs (lane != null && (existingLane == null || existingLane == "default")) {
            inherit lane;
          };
    in
    {
      inherit
        annotateCoreUplinkLane
        annotateMergedLinkLane
        linkSpecConnectsEndpoints
        ;
    };
}
