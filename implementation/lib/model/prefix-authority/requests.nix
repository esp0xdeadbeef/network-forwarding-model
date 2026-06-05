{ lib, self ? { outPath = ./.; }, ... }:

let
  clientPublicAuthorityClasses = [
    "delegated-client-prefix"
    "provider-owned-client-prefix"
    "routed-client-prefix"
    "routed-public-ipv4"
    "tunneled-client-prefix"
  ];

  clientGuaAuthorityClasses = [
    "delegated-client-prefix"
    "provider-owned-client-prefix"
    "routed-client-prefix"
    "tunneled-client-prefix"
  ];

  requestId =
    idx: r:
    toString (r.id or r.name or "request-${toString idx}");

  authorityAssigned =
    authority:
    authority != null && (authority.reservationState or "assigned") == "assigned";

  authorityConsumerAllowed =
    authority: consumer:
    authorityAssigned authority && ((authority.consumerEligibility.${consumer} or false) == true);

  modeledReturnRoute =
    request:
    let
      route = request.returnRoute or request.returnPath or null;
      routes = request.returnRoutes or [ ];
      routeHasData =
        if route == null then
          false
        else if builtins.isBool route then
          route
        else if builtins.isString route then
          route != ""
        else if builtins.isAttrs route then
          (route.modeled or true) != false
          && (
            (route.id or null) != null
            || (route.dst or null) != null
            || (route.prefix or null) != null
            || (route.via or null) != null
            || (route.nextHop or null) != null
            || (route.interface or null) != null
            || (route.uplink or null) != null
            || (route.path or null) != null
          )
        else
          false;
    in
    routeHasData || (builtins.isList routes && routes != [ ]);

  routeExportConsumer =
    consumer:
    consumer == "assignment" || consumer == "route";

  interfaceRoleOf =
    request:
    toString (request.interfaceRole or request.role or request.interfaceKind or request.kind or "unknown");

  interfaceKindOf =
    request:
    toString (request.interfaceKind or request.kind or request.interfaceRole or request.role or "unknown");

  isUplinkPlacement =
    request:
    let
      role = interfaceRoleOf request;
      kind = interfaceKindOf request;
    in
    builtins.elem role [
      "core-uplink"
      "uplink"
      "uplink-facing"
      "wan"
    ]
    || builtins.elem kind [
      "uplink"
      "wan"
    ]
    || (request.uplink or null) != null;

  isTransitPlacement =
    request:
    let
      role = interfaceRoleOf request;
      kind = interfaceKindOf request;
    in
    (request.transitHop or false) == true
    || builtins.elem role [
      "downstream-selector"
      "p2p-transit"
      "policy"
      "transit"
      "upstream-selector"
    ]
    || builtins.elem kind [
      "p2p"
      "transit"
    ];

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

  classifyRequest =
    records: idx: request:
    let
      authorityId = request.authorityId or null;
      authority = if authorityId != null && records ? "${authorityId}" then records.${authorityId} else null;
      consumer = toString (request.consumer or "route");
      assigned = authorityAssigned authority;
      consumerAllowed = authorityConsumerAllowed authority consumer;
      allowed = consumerAllowed;
      reason =
        if authority == null then
          "unassigned-prefix-authority"
        else if (authority.reservationState or "assigned") != "assigned" then
          "reserved-prefix-authority"
        else if !consumerAllowed then
          "invalid-consumer-for-authority-class"
        else
          "allowed";
    in
    {
      id = requestId idx request;
      inherit
        allowed
        consumer
        reason
        ;
      authorityId = authorityId;
      authorityClass = if authority == null then null else authority.authorityClass;
      reservationState = if authority == null then "unassigned" else authority.reservationState or "assigned";
    }
    // lib.optionalAttrs ((request.family or null) != null) { family = request.family; }
    // lib.optionalAttrs ((request.prefix or null) != null) { prefix = toString request.prefix; }
    // lib.optionalAttrs ((request.sourceFile or null) != null) { sourceFile = toString request.sourceFile; };

  classifyReturnRoutePrecondition =
    records: idx: request:
    let
      authorityId = request.authorityId or null;
      authority = if authorityId != null && records ? "${authorityId}" then records.${authorityId} else null;
      consumer = toString (request.consumer or "route");
      authorityClass = if authority == null then null else authority.authorityClass;
      publicClientAuthority = authorityClass != null && builtins.elem authorityClass clientPublicAuthorityClasses;
      relevantConsumer = routeExportConsumer consumer;
      hasReturnRoute = modeledReturnRoute request;
      allowed = authorityConsumerAllowed authority consumer && publicClientAuthority && relevantConsumer && hasReturnRoute;
      reason =
        if authority == null then
          "unassigned-prefix-authority"
        else if (authority.reservationState or "assigned") != "assigned" then
          "reserved-prefix-authority"
        else if !((authority.consumerEligibility.${consumer} or false) == true) then
          "invalid-consumer-for-authority-class"
        else if !publicClientAuthority then
          "invalid-public-prefix-authority"
        else if !relevantConsumer then
          "not-route-export-or-assignment-consumer"
        else if !hasReturnRoute then
          "missing-modeled-return-route"
        else
          "allowed";
    in
    {
      id = requestId idx request;
      gampId = "FS-360-HDS-010-SDS-010-SMS-020";
      inherit
        allowed
        consumer
        reason
        ;
      authorityId = authorityId;
      authorityClass = authorityClass;
      returnRouteModeled = hasReturnRoute;
    }
    // lib.optionalAttrs ((request.family or null) != null) { family = request.family; }
    // lib.optionalAttrs ((request.prefix or null) != null) { prefix = toString request.prefix; }
    // lib.optionalAttrs ((request.sourceFile or null) != null) { sourceFile = toString request.sourceFile; };

  classifyGuaPlacementPrecondition =
    records: idx: request:
    let
      authorityId = request.authorityId or null;
      authority = if authorityId != null && records ? "${authorityId}" then records.${authorityId} else null;
      authorityClass = if authority == null then null else authority.authorityClass;
      family = request.family or (if authority == null then null else authority.family);
      clientGuaAuthority = authorityClass != null && builtins.elem authorityClass clientGuaAuthorityClasses;
      transitPlacement = isTransitPlacement request;
      uplinkPlacement = isUplinkPlacement request;
      invalidTransitPlacement = clientGuaAuthority && family == 6 && transitPlacement && !uplinkPlacement;
      allowed = authorityAssigned authority && clientGuaAuthority && family == 6 && !invalidTransitPlacement;
      reason =
        if authority == null then
          "unassigned-prefix-authority"
        else if (authority.reservationState or "assigned") != "assigned" then
          "reserved-prefix-authority"
        else if family != 6 then
          "not-ipv6-gua-placement"
        else if !clientGuaAuthority then
          "invalid-gua-prefix-authority"
        else if invalidTransitPlacement then
          "non-uplink-transit-gua-placement"
        else
          "allowed";
    in
    {
      id = requestId idx request;
      gampId = "FS-360-HDS-010-SDS-010-SMS-030";
      inherit
        allowed
        reason
        ;
      authorityId = authorityId;
      authorityClass = authorityClass;
      family = family;
      interfaceRole = interfaceRoleOf request;
      interfaceKind = interfaceKindOf request;
      transitHop = transitPlacement;
      uplinkPlacement = uplinkPlacement;
    }
    // lib.optionalAttrs ((request.prefix or null) != null) { prefix = toString request.prefix; }
    // lib.optionalAttrs ((request.sourceFile or null) != null) { sourceFile = toString request.sourceFile; };

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
    in
    {
      id = requestId idx request;
      gampId = "FS-480-HDS-010-SDS-010-SMS-020";
      inherit
        allowed
        consumer
        reason
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
  classify =
    records: requests:
    map (args: classifyRequest records args.fst args.snd) (lib.imap0 (idx: value: {
      fst = idx;
      snd = value;
    }) requests);

  classifyReturnRoutePreconditions =
    records: requests:
    map (args: classifyReturnRoutePrecondition records args.fst args.snd) (lib.imap0 (idx: value: {
      fst = idx;
      snd = value;
    }) requests);

  classifyGuaPlacementPreconditions =
    records: requests:
    map (args: classifyGuaPlacementPrecondition records args.fst args.snd) (lib.imap0 (idx: value: {
      fst = idx;
      snd = value;
    }) requests);

  classifyRouteImportConstraints =
    records: requests:
    map (args: classifyRouteImportConstraint records args.fst args.snd) (lib.imap0 (idx: value: {
      fst = idx;
      snd = value;
    }) requests);
}
