{ lib, helpers }:

let
  diagnostics = import ./requests-classify-import-diagnostics.nix { inherit lib; };

  inherit (helpers)
    requestId
    authorityAssigned
    authorityConsumerAllowed
    routeExportConsumer
    interfaceRoleOf
    interfaceKindOf
    isUplinkPlacement
    isTransitPlacement
    ;

  normalizeStringList =
    value:
    if value == null then
      [ ]
    else if builtins.isList value then
      map toString value
    else
      [ (toString value) ];

  fieldOrNull =
    request: names:
    let
      matches = lib.filter (name: request ? "${name}" && request.${name} != null) names;
    in
    if matches == [ ] then null else request.${builtins.head matches};

  scopeRank =
    scope:
    let
      order = [
        "node"
        "access"
        "tenant"
        "site"
        "remote-site"
        "provider"
        "global"
      ];
      idx = lib.lists.findFirstIndex (item: item == toString scope) null order;
    in
    if idx == null then null else idx;

  classifyRouteImportConstraint =
    records: idx: request:
    let
      authorityId = request.authorityId or null;
      authority = if authorityId != null && records ? "${authorityId}" then records.${authorityId} else null;
      authorityClass = if authority == null then null else authority.authorityClass;
      authorityOwner = if authority == null then null else authority.owner or null;
      consumer = toString (request.consumer or "route");
      routePrefix = fieldOrNull request [ "routePrefix" "prefix" "routeDst" "dst" ];
      allowedPrefixes = normalizeStringList (fieldOrNull request [ "allowedPrefixes" "allowedPrefixList" ]);
      sourcePeerOrProvider = fieldOrNull request [ "sourcePeerOrProvider" "sourcePeer" "provider" "peer" ];
      allowedSources = normalizeStringList (fieldOrNull request [ "allowedSources" "allowedPeers" "allowedProviders" ]);
      routePurpose = fieldOrNull request [ "routePurpose" "purpose" ];
      allowedPurposes = normalizeStringList (fieldOrNull request [ "allowedPurposes" "purposes" ]);
      destinationOwner = fieldOrNull request [ "destinationOwner" "destinationOwnership" "owner" ];
      allowedDestinationOwners = normalizeStringList (fieldOrNull request [ "allowedDestinationOwners" "destinationOwners" ]);
      maximumScope = fieldOrNull request [ "maximumScope" "maxScope" ];
      routeScope = fieldOrNull request [ "routeScope" "scope" ];
      exportRequested = fieldOrNull request [ "exportRequested" "attemptExport" "requestedExport" ];
      exportEligible = fieldOrNull request [ "exportEligible" "allowedExport" ];
      rejectionBehavior = fieldOrNull request [ "rejectionBehavior" "rejectBehavior" ];
      conflictType = fieldOrNull request [ "conflictType" "routeConflictType" ];
      conflictSource = fieldOrNull request [ "conflictSource" "conflictingSource" ];
      authorityFreeRouteAsAllowed = (request.authorityFreeRouteAsAllowed or false) == true;
      gampId = toString (request.gampId or "FS-480-HDS-010-SDS-010-SMS-020");
      allowedPrefixMatch = routePrefix != null && builtins.elem (toString routePrefix) allowedPrefixes;
      sourceAllowed = sourcePeerOrProvider != null && builtins.elem (toString sourcePeerOrProvider) allowedSources;
      purposeAllowed = routePurpose != null && builtins.elem (toString routePurpose) allowedPurposes;
      ownershipAllowed =
        destinationOwner != null
        && builtins.elem (toString destinationOwner) allowedDestinationOwners
        && (authorityOwner == null || authorityOwner == toString destinationOwner);
      maximumScopeRank = if maximumScope == null then null else scopeRank maximumScope;
      routeScopeRank = if routeScope == null then null else scopeRank routeScope;
      scopeAllowed =
        maximumScopeRank != null
        && routeScopeRank != null
        && routeScopeRank <= maximumScopeRank;
      exportRequestedBool = exportRequested == true;
      exportEligibleBool = exportEligible == true;
      exportAllowed = (!exportRequestedBool) || exportEligibleBool;
      rejectionBehaviorPresent = rejectionBehavior != null;
      allowed =
        authorityConsumerAllowed authority consumer
        && allowedPrefixMatch
        && sourceAllowed
        && purposeAllowed
        && ownershipAllowed
        && scopeAllowed
        && exportAllowed
        && rejectionBehaviorPresent;
      reason =
        if authority == null then
          "unassigned-prefix-authority"
        else if (authority.reservationState or "assigned") != "assigned" then
          "reserved-prefix-authority"
        else if !((authority.consumerEligibility.${consumer} or false) == true) then
          "invalid-consumer-for-authority-class"
        else if routePrefix == null || allowedPrefixes == [ ] then
          "missing-allowed-prefix-constraint"
        else if !allowedPrefixMatch then
          "route-prefix-not-allowed"
        else if sourcePeerOrProvider == null || allowedSources == [ ] then
          "missing-source-peer-or-provider"
        else if !sourceAllowed then
          "unexpected-source-peer-or-provider"
        else if routePurpose == null || allowedPurposes == [ ] then
          "missing-route-purpose"
        else if !purposeAllowed then
          "unexpected-route-purpose"
        else if destinationOwner == null || allowedDestinationOwners == [ ] then
          "missing-destination-ownership"
        else if !ownershipAllowed then
          "destination-ownership-conflict"
        else if maximumScope == null || routeScope == null || maximumScopeRank == null || routeScopeRank == null then
          "missing-maximum-scope"
        else if !scopeAllowed then
          "maximum-scope-exceeded"
        else if exportRequested == null || exportEligible == null then
          "missing-export-eligibility"
        else if !exportAllowed then
          "unauthorized-export"
        else if !rejectionBehaviorPresent then
          "missing-rejection-behavior"
        else
          "allowed";
      diagnosticCode =
        diagnostics.codeFor {
          inherit
            allowed
            authority
            authorityFreeRouteAsAllowed
            reason
            conflictType
            ;
        };
      diagnostic =
        diagnostics.recordFor {
          inherit
            allowed
            diagnosticCode
            reason
            authorityId
            routePrefix
            sourcePeerOrProvider
            routePurpose
            destinationOwner
            conflictType
            conflictSource
            ;
        };
      reachabilityClassification =
        diagnostics.reachabilityClassificationFor {
          inherit
            allowed
            diagnosticCode
            ;
        };
    in
    {
      id = requestId idx request;
      gampId = gampId;
      inherit
        allowed
        consumer
        reason
        diagnostic
        diagnosticCode
        reachabilityClassification
        ;
      authorityId = authorityId;
      authorityClass = authorityClass;
      authorityOwner = authorityOwner;
      routePrefix = if routePrefix == null then null else toString routePrefix;
      allowedPrefixes = allowedPrefixes;
      sourcePeerOrProvider = if sourcePeerOrProvider == null then null else toString sourcePeerOrProvider;
      allowedSources = allowedSources;
      routePurpose = if routePurpose == null then null else toString routePurpose;
      allowedPurposes = allowedPurposes;
      destinationOwner = if destinationOwner == null then null else toString destinationOwner;
      allowedDestinationOwners = allowedDestinationOwners;
      maximumScope = if maximumScope == null then null else toString maximumScope;
      routeScope = if routeScope == null then null else toString routeScope;
      exportRequested = exportRequestedBool;
      exportEligible = exportEligibleBool;
      rejectionBehavior = if rejectionBehavior == null then null else toString rejectionBehavior;
    };

in
{
  inherit classifyRouteImportConstraint;
}
