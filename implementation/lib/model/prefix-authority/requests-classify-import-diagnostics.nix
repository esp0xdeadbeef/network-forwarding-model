{ lib }:

let
  codeFor =
    { allowed
    , authority
    , authorityFreeRouteAsAllowed
    , reason
    , conflictType
    }:
    if allowed then
      null
    else if authority == null && authorityFreeRouteAsAllowed then
      "AUTHORITY_FREE_ROUTE_AS_ALLOWED"
    else if authority == null then
      "MISSING_ROUTE_IMPORT_AUTHORITY"
    else if reason == "route-prefix-not-allowed" && conflictType == "overlap" then
      "OVERLAPPING_ROUTE_ADVERTISEMENT"
    else if reason == "unexpected-source-peer-or-provider" then
      "UNAUTHORIZED_ROUTE_SOURCE"
    else if reason == "route-prefix-not-allowed" then
      "ROUTE_IMPORT_PREFIX_OUT_OF_CONSTRAINT"
    else if reason == "missing-allowed-prefix-constraint" then
      "MISSING_ROUTE_IMPORT_CONSTRAINT"
    else if reason == "maximum-scope-exceeded" then
      "ROUTE_IMPORT_SCOPE_EXCEEDED"
    else if reason == "unauthorized-export" then
      "UNAUTHORIZED_ROUTE_EXPORT"
    else
      "INVALID_ROUTE_IMPORT_CONSTRAINT";

  recordFor =
    { allowed
    , diagnosticCode
    , reason
    , authorityId
    , routePrefix
    , sourcePeerOrProvider
    , routePurpose
    , destinationOwner
    , conflictType
    , conflictSource
    }:
    if allowed then
      null
    else
      {
        code = diagnosticCode;
        reason = reason;
        authorityId = authorityId;
        routePrefix = if routePrefix == null then null else toString routePrefix;
        sourcePeerOrProvider = if sourcePeerOrProvider == null then null else toString sourcePeerOrProvider;
        routePurpose = if routePurpose == null then null else toString routePurpose;
        destinationOwner = if destinationOwner == null then null else toString destinationOwner;
      }
      // lib.optionalAttrs (conflictType != null) { conflictType = toString conflictType; }
      // lib.optionalAttrs (conflictSource != null) { conflictSource = toString conflictSource; };

  reachabilityClassificationFor =
    { allowed, diagnosticCode }:
    if allowed then
      "allowed"
    else if diagnosticCode == "MISSING_ROUTE_IMPORT_AUTHORITY" || diagnosticCode == "AUTHORITY_FREE_ROUTE_AS_ALLOWED" then
      "ambiguous"
    else
      "denied";
in
{
  inherit
    codeFor
    recordFor
    reachabilityClassificationFor
    ;
}
