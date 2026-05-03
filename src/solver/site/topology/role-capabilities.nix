{ }:

let
  baseTransitFunctions = [
    "router-identity"
    "transit-forwarder"
  ];

  roleFlagsFor =
    {
      role,
      exitNode,
      upstreamSelection,
    }:
    {
      isAccess = role == "access";
      isDownstreamSelector = role == "downstream-selector";
      isPolicy = role == "policy";
      isUpstreamSelector = upstreamSelection;
      isUplinkCore = exitNode;
    };
in
{
  forwardingFunctionsFor =
    args:
    let
      flags = roleFlagsFor args;
    in
    if flags.isAccess then
      baseTransitFunctions
      ++ [
        "access-gateway"
        "connected-prefix-origin"
        "tenant-edge"
        "traversal-entry"
      ]
    else if flags.isDownstreamSelector then
      baseTransitFunctions
      ++ [
        "downstream-selector"
      ]
    else if flags.isPolicy then
      baseTransitFunctions
      ++ [
        "policy-enforcer"
      ]
    else if flags.isUpstreamSelector then
      baseTransitFunctions
      ++ [
        "egress-selector"
        "upstream-selector"
      ]
    else if flags.isUplinkCore then
      baseTransitFunctions
      ++ [
        "external-egress"
        "uplink-anchor"
      ]
    else
      baseTransitFunctions;

  forwardingResponsibilityFor =
    args:
    let
      flags = roleFlagsFor args;
    in
    {
      anchorsExternalUplinks = flags.isUplinkCore;
      carriesTransit = true;
      enforcesPolicy = flags.isPolicy;
      explicit = true;
      participatesInUpstreamSelection = flags.isUplinkCore || flags.isUpstreamSelector;
      terminatesOverlays = false;
      terminatesTenants = flags.isAccess;
    };

  routingAuthorityFor =
    args:
    let
      flags = roleFlagsFor args;
    in
    {
      connectedReachability = true;
      defaultReachability = false;
      exitsSite = flags.isUplinkCore;
      explicit = true;
      internalReachability = true;
      overlayReachability = false;
      selectsUpstream = flags.isUpstreamSelector;
      uplinkLearnedReachability = false;
    };

  traversalParticipationFor =
    args:
    let
      flags = roleFlagsFor args;
    in
    {
      enforcement = flags.isPolicy;
      exit = flags.isUplinkCore;
      explicit = true;
      ingress = flags.isAccess;
      participates = true;
      transit = true;
      upstreamSelection = flags.isUpstreamSelector;
    };
}
