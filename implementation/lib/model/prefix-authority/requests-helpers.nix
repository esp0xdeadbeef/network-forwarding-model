{ lib, ... }:

let
  interfaceRoleOf =
    request:
    toString (request.interfaceRole or request.role or request.interfaceKind or request.kind or "unknown");

  interfaceKindOf =
    request:
    toString (request.interfaceKind or request.kind or request.interfaceRole or request.role or "unknown");
in
{
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

  inherit interfaceRoleOf interfaceKindOf;

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
}
