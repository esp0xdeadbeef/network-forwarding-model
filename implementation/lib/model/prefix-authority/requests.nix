{ lib, self ? { outPath = ./.; }, ... }:

let
  helpers = import ./requests-helpers.nix { inherit lib; };
  classifyImportMod = import ./requests-classify-import.nix { inherit lib helpers; };

  inherit (helpers)
    clientPublicAuthorityClasses
    clientGuaAuthorityClasses
    requestId
    authorityAssigned
    authorityConsumerAllowed
    modeledReturnRoute
    routeExportConsumer
    interfaceRoleOf
    interfaceKindOf
    isUplinkPlacement
    isTransitPlacement
    ;

  inherit (classifyImportMod) classifyRouteImportConstraint;

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
