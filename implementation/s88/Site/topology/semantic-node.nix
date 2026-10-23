{
  lib,
  self ? {
    outPath = ./.;
  },
  ...
}:

let
  roleCapabilities = import ./role-capabilities.nix { };
  overlayNameSet = import ./overlay-name-set.nix { inherit lib self; };
  overlaysTopology = import ./overlays.nix { inherit lib self; };

  # FS-460: a node terminates an overlay when it is the modeled terminateOn
  # target of any overlay.  This is behavior (the overlay's endpoint identity),
  # not a per-role constant, so it is derived from the intent.
  terminatesOverlay =
    site: nodeName:
    let
      name = toString nodeName;
      # Only the intent form (transport.overlays) defines which node terminates
      # an overlay.  `overlayReachability` is the resolved per-overlay EXIT /
      # peer-route record: its terminateOn is merged across every peer
      # (mergeReachability: `lib.unique (existing.terminateOn ++ item.terminateOn)`)
      # and it also carries the node that merely holds the peer route.  Unions
      # of that record are not role authority, so consulting it made a plain
      # egress core look like an overlay terminator and moved client-egress
      # forwarding rules (WAN lane -> uplink::<overlay> lane) onto it.
      #
      # Roles come from intent; the resolved peer-route record only describes
      # reachability toward the peer.  Keep them separate.
      transportOverlays = ((site.transport or { }).overlays or [ ]);
      overlays = if builtins.isList transportOverlays then transportOverlays else [ ];
    in
    builtins.any (
      overlay:
      builtins.isAttrs overlay
      && builtins.elem name (
        overlaysTopology.overlayTargetNamesFrom (
          overlay.terminateOn or overlay.terminatesOn or overlay.terminatedOn or null
        )
      )
    ) overlays;

  sortedUnique =
    xs:
    lib.sort (a: b: toString a < toString b) (lib.unique (map toString (lib.filter (x: x != null) xs)));
  listOrEmpty = value: if builtins.isList value then value else [ ];
  attrsOrEmpty = value: if builtins.isAttrs value then value else { };
  nat66Egress = import ./semantic-node/nat66-egress.nix {
    inherit
      lib
      sortedUnique
      listOrEmpty
      attrsOrEmpty
      ;
  };
  nat44Egress = import ./semantic-node/nat44-egress.nix {
    inherit
      lib
      sortedUnique
      listOrEmpty
      attrsOrEmpty
      ;
  };

  ifaceUplinkName =
    iface:
    if builtins.isAttrs iface && iface ? uplink && iface.uplink != null then
      toString iface.uplink
    else if builtins.isAttrs iface && iface ? upstream && iface.upstream != null then
      toString iface.upstream
    else
      null;

  wanInterfacesForNode =
    node:
    let
      interfaces = node.interfaces or { };
      names = builtins.attrNames interfaces;
    in
    sortedUnique (
      lib.filter (
        ifName:
        let
          iface = interfaces.${ifName};
          kind = iface.kind or null;
          carrier = iface.carrier or null;
          type = iface.type or null;
        in
        kind == "wan" || carrier == "wan" || type == "wan"
      ) names
    );

  declaredUplinksForNode =
    node:
    if node ? uplinks && builtins.isAttrs node.uplinks then
      sortedUnique (builtins.attrNames node.uplinks)
    else
      [ ];

  build =
    {
      nodeName,
      node,
      site,
      role,
      siteExternalDomains,
      siteUplinkCoreNames,
      siteUplinkNames ? [ ],
      siteEgressCoreNames ? siteUplinkCoreNames,
      siteEgressUplinkNames ? siteUplinkNames,
    }:
    let
      exitNode = lib.elem nodeName siteEgressCoreNames;
      uplinkAnchor = lib.elem nodeName siteUplinkCoreNames;
      upstreamSelection = role == "upstream-selector" && siteEgressUplinkNames != [ ];
      eligible = exitNode || upstreamSelection;

      wanIfaces = wanInterfacesForNode node;
      interfaces = node.interfaces or { };

      interfaceUplinks = sortedUnique (map (ifName: ifaceUplinkName interfaces.${ifName}) wanIfaces);
      nodeSpecificUplinks = sortedUnique ((declaredUplinksForNode node) ++ interfaceUplinks);
      eligibleUplinks = lib.filter (uplink: builtins.elem uplink siteEgressUplinkNames) (
        if nodeSpecificUplinks != [ ] then nodeSpecificUplinks else siteEgressUplinkNames
      );
      overlayUplinkNameSet = overlayNameSet site;
      nat66ByUplink =
        if eligible then
          nat66Egress.forUplinks site overlayUplinkNameSet eligibleUplinks (
            attrsOrEmpty (node.uplinks or null)
          )
        else
          { };
      nat44ByUplink =
        if eligible then
          nat44Egress.forUplinks site overlayUplinkNameSet eligibleUplinks (
            attrsOrEmpty (node.uplinks or null)
          )
        else
          { };

      effectiveUplinks = if eligible then eligibleUplinks else [ ];
      effectiveWanInterfaces =
        if !eligible then
          [ ]
        else if wanIfaces != [ ] then
          wanIfaces
        else
          eligibleUplinks;

      capabilityArgs = {
        inherit
          exitNode
          role
          uplinkAnchor
          upstreamSelection
          ;
        terminatesOverlays = terminatesOverlay site nodeName;
      };
    in
    {
      egressIntent = {
        eligible = eligible;
        exit = exitNode;
        explicit = true;
        externalDomains = if eligible then siteExternalDomains else [ ];
        nat66 = nat66ByUplink;
        nat44 = nat44ByUplink;
        uplinks = effectiveUplinks;
        upstreamSelection = upstreamSelection;
        wanInterfaces = effectiveWanInterfaces;
      };

      forwardingFunctions = roleCapabilities.forwardingFunctionsFor capabilityArgs;
      forwardingResponsibility = roleCapabilities.forwardingResponsibilityFor capabilityArgs;
      routingAuthority = roleCapabilities.routingAuthorityFor capabilityArgs;
      traversalParticipation = roleCapabilities.traversalParticipationFor capabilityArgs;
    };

in
{
  inherit build;
}
