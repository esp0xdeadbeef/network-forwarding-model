{ lib }:

let
  roleCapabilities = import ./role-capabilities.nix { };

  sortedUnique =
    xs:
    lib.sort (a: b: toString a < toString b) (lib.unique (map toString (lib.filter (x: x != null) xs)));

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
      role,
      siteUplinkCoreNames,
      siteUplinkNames,
      siteExternalDomains,
    }:
    let
      exitNode = lib.elem nodeName siteUplinkCoreNames;
      upstreamSelection = role == "upstream-selector";
      eligible = exitNode || upstreamSelection;

      wanIfaces = wanInterfacesForNode node;
      interfaces = node.interfaces or { };

      interfaceUplinks = sortedUnique (map (ifName: ifaceUplinkName interfaces.${ifName}) wanIfaces);
      nodeSpecificUplinks = sortedUnique ((declaredUplinksForNode node) ++ interfaceUplinks);
      eligibleUplinks = if nodeSpecificUplinks != [ ] then nodeSpecificUplinks else siteUplinkNames;

      effectiveUplinks = if eligible then eligibleUplinks else sortedUnique interfaceUplinks;
      effectiveWanInterfaces =
        if wanIfaces != [ ] then
          wanIfaces
        else if eligible then
          eligibleUplinks
        else
          [ ];

      capabilityArgs = {
        inherit exitNode role upstreamSelection;
      };
    in
    {
      egressIntent = {
        eligible = eligible;
        exit = exitNode;
        explicit = true;
        externalDomains = if eligible then siteExternalDomains else [ ];
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
