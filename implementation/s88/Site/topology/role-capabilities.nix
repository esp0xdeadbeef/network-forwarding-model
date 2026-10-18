{ ... }:

let
  baseTransitFunctions = [
    "router-identity"
    "transit-forwarder"
  ];

  roleFlagsFor =
    { role
    , exitNode
    , uplinkAnchor ? false
    , upstreamSelection
    , terminatesOverlays ? false
    ,
    }:
    {
      isAccess = role == "access";
      isDownstreamSelector = role == "downstream-selector";
      isPolicy = role == "policy";
      isUpstreamSelector = upstreamSelection;
      isUplinkCore = uplinkAnchor;
      isEgressExit = exitNode;
      terminatesOverlays = terminatesOverlays;
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
      ++ (if flags.isEgressExit then [ "external-egress" ] else [ ])
      ++ [ "uplink-anchor" ]
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
      participatesInUpstreamSelection = flags.isEgressExit || flags.isUpstreamSelector;
      # FS-460: behavior derived from the modeled overlay endpoints, not a
      # per-role constant.  A core that terminates an overlay is its exit
      # surface toward the upstream-selector.
      terminatesOverlays = flags.terminatesOverlays;
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
      exitsSite = flags.isEgressExit;
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
      exit = flags.isEgressExit;
      explicit = true;
      ingress = flags.isAccess;
      participates = true;
      transit = true;
      upstreamSelection = flags.isUpstreamSelector;
    };
}
