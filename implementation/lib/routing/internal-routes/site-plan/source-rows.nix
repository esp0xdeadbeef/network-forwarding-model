{ lib }:

{
  build =
    { includeOverlay
    , includeP2p
    , includeTenant
    , mode ? "none"
    , nodeNames
    , nodes
    , remotePrefixFacts
    ,
    }:
    let
      helpers = import ./source-rows-helpers.nix {
        inherit lib mode nodes remotePrefixFacts;
      };

      inherit (helpers)
        enrichEntry
        normalizeTenantEntry
        sourceEligibleForEntry
        ;

      entriesByKind =
        map enrichEntry (
          (if includeP2p then remotePrefixFacts.p2pEntries else [ ])
          ++ (if includeTenant then map normalizeTenantEntry (remotePrefixFacts.tenantOwnerEntries or [ ]) else [ ])
          ++ (if includeOverlay then remotePrefixFacts.overlayRouteEntries else [ ])
        );

      resolutionKey =
        nodeName: entry:
        let
          e = entry;
          routeScope = e.routeScope or { };
        in
        "${nodeName}|${toString (e.owner or "")}|${toString (e.kind or "")}|${toString (e.overlay or "")}|${toString (e.peerSite or "")}|${toString (routeScope.access or "")}|${toString (routeScope.uplink or "")}|${toString (routeScope.serviceName or "")}";

      appendEntry =
        groups: nodeName: entry:
        let
          key = resolutionKey nodeName entry;
          current = groups.${key} or {
            inherit nodeName;
            entries = [ ];
          };
        in
        groups
        // {
          "${key}" = current // {
            entries = current.entries ++ [ entry ];
          };
        };

      appendScopedRows =
        groups: eligibleNodeNames: entry:
        builtins.foldl'
          (acc: nodeName: appendEntry acc nodeName entry)
          groups
          eligibleNodeNames;

      addEntryGroups =
        groups: entry:
        let
          eligibleNodeNames = builtins.filter (nodeName: sourceEligibleForEntry nodeName entry) nodeNames;
          serviceScopes =
            if (entry.kind or null) == "tenant" then
              remotePrefixFacts.serviceRouteScopesByOwner.${entry.owner} or [ ]
            else
              [ ];
          groupedBase = appendScopedRows groups eligibleNodeNames entry;
        in
        builtins.foldl'
          (
            acc: scope:
            appendScopedRows acc eligibleNodeNames (entry // { routeScope = scope; })
          )
          groupedBase
          serviceScopes;

      remoteGroups = builtins.foldl' addEntryGroups { } entriesByKind;
      remoteGroupValues = builtins.attrValues remoteGroups;
      eligiblePairCount = builtins.foldl' (acc: group: acc + builtins.length (group.entries or [ ])) 0 remoteGroupValues;
      rejectedPairCount =
        (builtins.length entriesByKind * builtins.length nodeNames) - eligiblePairCount;
      classCounts =
        builtins.mapAttrs (_: records: builtins.length records) (
          builtins.groupBy (entry: entry.aggregationClass or "unknown") entriesByKind
        );
    in
    {
      inherit entriesByKind;
      inherit remoteGroups;
      diagnostics = {
        routeAtomIndex = {
          sms = "FS-940-HDS-010-SDS-020-SMS-020";
          authority = "site-plan/source-rows";
          builtBeforeRouteRows = true;
          atomCount = builtins.length entriesByKind;
          atoms = map (entry: entry.routeAtom) entriesByKind;
          aggregationClasses = classCounts;
          requiredFields = [
            "id"
            "family"
            "destination"
            "sourceFile"
            "owner"
            "kind"
            "overlay"
            "uplink"
            "exceptionClass"
            "aggregationClass"
          ];
        };
        sourceEligibilityMatrix = {
          sms = "FS-940-HDS-010-SDS-020-SMS-030";
          authority = "site-plan/source-rows";
          groupedOncePerSite = true;
          keyFields = [
            "sourceNode"
            "routeAtomId"
            "owner"
            "kind"
            "overlay"
            "uplink"
            "access"
            "serviceName"
          ];
          remoteGroupCount = builtins.length (builtins.attrNames remoteGroups);
          inherit eligiblePairCount rejectedPairCount;
        };
      };
    };
}
