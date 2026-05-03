{ lib }:

{
  derive =
    {
      site,
      unitNames,
      topologyPairs,
      rolesResult,
      wanResult,
    }:
    let
      firstUnitByRole =
        role:
        let
          names = lib.sort (a: b: a < b) unitNames;
          hits = lib.filter (n: rolesResult.roleFromInput (toString n) == role) names;
        in
        if hits == [ ] then null else toString (builtins.head hits);

      downstreamSelectorUnit = firstUnitByRole "downstream-selector";
      upstreamSelectorUnit = firstUnitByRole "upstream-selector";
      policyUnit = if rolesResult.policyUnit == null then null else toString rolesResult.policyUnit;
      accessUnitNames =
        let
          names = lib.sort (a: b: a < b) unitNames;
        in
        map toString (lib.filter (n: rolesResult.roleFromInput (toString n) == "access") names);

      tenantsByAccessUnit =
        let
          attachments = site.attachments or [ ];
          step =
            acc: a:
            if !(builtins.isAttrs a) then
              acc
            else
              let
                unit = toString (a.unit or "");
                kind = toString (a.kind or "");
                name = toString (a.name or "");
              in
              if unit == "" || kind != "tenant" || name == "" then
                acc
              else
                acc
                // {
                  "${unit}" = (acc.${unit} or [ ]) ++ [ name ];
                };
        in
        builtins.foldl' step { } attachments;

      relationToUplinkNames =
        rel:
        let
          to = rel.to or { };
          kind = to.kind or null;
          uplinks = to.uplinks or null;
          name = to.name or null;
        in
        if kind != "external" then
          [ ]
        else if builtins.isList uplinks then
          map toString uplinks
        else if name != null && toString name != "" then
          [ (toString name) ]
        else
          [ ];

      relationAppliesToAccessUnit =
        unit: rel:
        let
          from = rel.from or { };
          unitTenants = tenantsByAccessUnit.${unit} or [ ];
          kind = from.kind or null;
        in
        if kind == "tenant" then
          builtins.elem (toString (from.name or "")) unitTenants
        else if kind == "tenant-set" then
          let
            members = if builtins.isList (from.members or null) then map toString from.members else [ ];
          in
          lib.any (t: builtins.elem t members) unitTenants
        else
          false;

      allowedUplinksByAccessUnit =
        let
          relations = site.communicationContract.allowedRelations or [ ];
          hasAnyAllowRelation = lib.any (rel: (rel.action or null) == "allow") relations;

          allUplinkNames =
            let
              cores = site.upstreams.cores or { };
              coreNames = builtins.attrNames cores;
              names = lib.concatMap (
                coreName: map (u: toString (u.name or "")) (cores.${coreName} or [ ])
              ) coreNames;
            in
            lib.sort (a: b: a < b) (lib.unique (lib.filter (s: s != "") names));

          mkForUnit =
            unit:
            let
              uplinks =
                if !hasAnyAllowRelation then
                  allUplinkNames
                else
                  lib.concatMap (
                    rel:
                    if (rel.action or null) == "allow" && relationAppliesToAccessUnit unit rel then
                      relationToUplinkNames rel
                    else
                      [ ]
                  ) relations;
            in
            {
              name = unit;
              value = lib.sort (a: b: a < b) (lib.unique (lib.filter (s: s != "") (map toString uplinks)));
            };
        in
        builtins.listToAttrs (map mkForUnit accessUnitNames);

      canonicalP2pLinkNameForEndpoints =
        endpointA: endpointB:
        let
          endpointAName = toString endpointA;
          endpointBName = toString endpointB;
          firstEndpoint = if endpointAName < endpointBName then endpointAName else endpointBName;
          secondEndpoint = if endpointAName < endpointBName then endpointBName else endpointAName;
        in
        "p2p-${firstEndpoint}-${secondEndpoint}";

      canonicalP2pLinkNameForEndpointsWithSuffix =
        endpointA: endpointB: suffix:
        "${canonicalP2pLinkNameForEndpoints endpointA endpointB}--${toString suffix}";

      baseP2pPairs = lib.filter (p: builtins.isList p && builtins.length p == 2) topologyPairs;

      linkSpecEndpointA =
        pair:
        if builtins.isList pair then
          toString (builtins.elemAt pair 0)
        else
          toString pair.a;

      linkSpecEndpointB =
        pair:
        if builtins.isList pair then
          toString (builtins.elemAt pair 1)
        else
          toString pair.b;

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

      annotateCoreUplinkLane =
        pair:
        let
          a = linkSpecEndpointA pair;
          b = linkSpecEndpointB pair;
          other =
            if upstreamSelectorUnit == null then
              null
            else if a == upstreamSelectorUnit then
              b
            else if b == upstreamSelectorUnit then
              a
            else
              null;
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
          other =
            if pair == null || upstreamSelectorUnit == null then
              null
            else if pair.a == upstreamSelectorUnit then
              pair.b
            else if pair.b == upstreamSelectorUnit then
              pair.a
            else
              null;
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

      basePairsWithoutSelectorBuses =
        if policyUnit == null then
          map annotateCoreUplinkLane baseP2pPairs
        else
          map annotateCoreUplinkLane (
            lib.filter (
              pair:
              let
                connectsDownstreamSelectorToPolicy =
                  downstreamSelectorUnit != null
                  && linkSpecConnectsEndpoints policyUnit downstreamSelectorUnit pair;
                connectsPolicyToUpstreamSelector =
                  upstreamSelectorUnit != null
                  && linkSpecConnectsEndpoints policyUnit upstreamSelectorUnit pair;
              in
              !(connectsDownstreamSelectorToPolicy || connectsPolicyToUpstreamSelector)
            ) baseP2pPairs
          );

      derivedLaneSpecs =
        if policyUnit == null then
          [ ]
        else
          (lib.concatMap (
            accessUnit:
            if downstreamSelectorUnit == null then
              [ ]
            else
              [
                {
                  a = policyUnit;
                  b = downstreamSelectorUnit;
                  lane = "access::${toString accessUnit}";
                  name =
                    canonicalP2pLinkNameForEndpointsWithSuffix policyUnit downstreamSelectorUnit
                      "access-${toString accessUnit}";
                }
              ]
          ) accessUnitNames)
          ++ (lib.concatMap (
            accessUnit:
            let
              uplinks = allowedUplinksByAccessUnit.${toString accessUnit} or [ ];
            in
            if upstreamSelectorUnit == null then
              [ ]
            else
              map (uplinkName: {
                a = policyUnit;
                b = upstreamSelectorUnit;
                lane = "access::${toString accessUnit}::uplink::${toString uplinkName}";
                name =
                  canonicalP2pLinkNameForEndpointsWithSuffix policyUnit upstreamSelectorUnit
                    "access-${toString accessUnit}--uplink-${toString uplinkName}";
              }) uplinks
          ) accessUnitNames);
    in
    {
      inherit
        accessUnitNames
        annotateMergedLinkLane
        downstreamSelectorUnit
        policyUnit
        upstreamSelectorUnit
        ;
      p2pLinkSpecs = basePairsWithoutSelectorBuses ++ derivedLaneSpecs;
    };
}
