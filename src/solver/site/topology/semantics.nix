{ lib }:

let
  roleCapabilities = import ./role-capabilities.nix { };

  sortedUnique =
    xs:
    lib.sort (a: b: toString a < toString b) (lib.unique (map toString (lib.filter (x: x != null) xs)));

  maybeOne = x: if x == null then [ ] else [ (toString x) ];

  firstByRole =
    names: roleOf: wanted:
    let
      matches = lib.filter (name: roleOf name == wanted) names;
    in
    if matches == [ ] then null else builtins.head matches;

  externalDomainNamesFromSite =
    site:
    let
      externals =
        if
          site ? domains
          && builtins.isAttrs site.domains
          && site.domains ? externals
          && builtins.isList site.domains.externals
        then
          site.domains.externals
        else
          [ ];
    in
    sortedUnique (
      map (
        external:
        if builtins.isAttrs external && external ? name && external.name != null then
          external.name
        else
          toString external
      ) externals
    );

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

  annotateSite =
    {
      site,
      rolesResult ? null,
      wanResult ? null,
    }:
    let
      nodes = site.nodes or { };
      nodeNames = sortedUnique (builtins.attrNames nodes);

      roleFromInput =
        if rolesResult != null && rolesResult ? roleFromInput then rolesResult.roleFromInput else (_: null);

      roleOf =
        nodeName:
        let
          fromNode =
            if nodes ? "${nodeName}" && builtins.isAttrs nodes.${nodeName} then
              nodes.${nodeName}.role or null
            else
              null;

          fromInput = roleFromInput nodeName;
        in
        if fromNode != null then
          toString fromNode
        else if fromInput != null then
          toString fromInput
        else
          null;

      coreNodeNames =
        if site ? coreNodeNames && builtins.isList site.coreNodeNames && site.coreNodeNames != [ ] then
          sortedUnique site.coreNodeNames
        else
          sortedUnique (lib.filter (name: roleOf name == "core") nodeNames);

      policyNodeName =
        if site ? policyNodeName && site.policyNodeName != null then
          toString site.policyNodeName
        else
          firstByRole nodeNames roleOf "policy";

      upstreamSelectorNodeName =
        if site ? upstreamSelectorNodeName && site.upstreamSelectorNodeName != null then
          toString site.upstreamSelectorNodeName
        else
          firstByRole nodeNames roleOf "upstream-selector";

      siteExternalDomains = externalDomainNamesFromSite site;

      siteUplinkCoreNames =
        if site ? uplinkCoreNames && builtins.isList site.uplinkCoreNames then
          sortedUnique site.uplinkCoreNames
        else if
          wanResult != null
          && wanResult ? declaredUplinkCores
          && builtins.isList wanResult.declaredUplinkCores
        then
          sortedUnique wanResult.declaredUplinkCores
        else if wanResult != null && wanResult ? uplinkCores && builtins.isList wanResult.uplinkCores then
          sortedUnique wanResult.uplinkCores
        else
          [ ];

      siteUplinkNames =
        let
          fromSite =
            if site ? uplinkNames && builtins.isList site.uplinkNames then
              sortedUnique site.uplinkNames
            else
              [ ];

          fromWan =
            if
              wanResult != null
              && wanResult ? declaredUplinkNames
              && builtins.isList wanResult.declaredUplinkNames
            then
              sortedUnique wanResult.declaredUplinkNames
            else if wanResult != null && wanResult ? uplinkNames && builtins.isList wanResult.uplinkNames then
              sortedUnique wanResult.uplinkNames
            else
              [ ];
        in
        if fromWan != [ ] then
          fromWan
        else if fromSite != [ ] then
          fromSite
        else
          siteExternalDomains;

      nodeSemantics = builtins.mapAttrs (
        nodeName: node:
        let
          role = roleOf nodeName;
          exitNode = lib.elem nodeName siteUplinkCoreNames;
          upstreamSelection = role == "upstream-selector";
          eligible = exitNode || upstreamSelection;

          wanIfaces = wanInterfacesForNode node;

          interfaceUplinks = sortedUnique (
            map (ifName: ifaceUplinkName ((node.interfaces or { }).${ifName})) wanIfaces
          );

          declaredNodeUplinks =
            if node ? uplinks && builtins.isAttrs node.uplinks then
              sortedUnique (builtins.attrNames node.uplinks)
            else
              [ ];

          effectiveUplinks =
            if eligible then
              sortedUnique (declaredNodeUplinks ++ interfaceUplinks ++ siteUplinkNames)
            else
              sortedUnique interfaceUplinks;

          effectiveWanInterfaces =
            if wanIfaces != [ ] then
              wanIfaces
            else if eligible then
              sortedUnique (declaredNodeUplinks ++ siteUplinkNames)
            else
              [ ];

          externalDomains = if eligible then siteExternalDomains else [ ];

          capabilityArgs = {
            inherit exitNode role upstreamSelection;
          };

          forwardingFunctions = roleCapabilities.forwardingFunctionsFor capabilityArgs;
          forwardingResponsibility = roleCapabilities.forwardingResponsibilityFor capabilityArgs;
          routingAuthority = roleCapabilities.routingAuthorityFor capabilityArgs;
          traversalParticipation = roleCapabilities.traversalParticipationFor capabilityArgs;

          egressIntent = {
            eligible = eligible;
            exit = exitNode;
            explicit = true;
            externalDomains = externalDomains;
            uplinks = effectiveUplinks;
            upstreamSelection = upstreamSelection;
            wanInterfaces = effectiveWanInterfaces;
          };
        in
        {
          inherit
            egressIntent
            forwardingFunctions
            forwardingResponsibility
            routingAuthority
            traversalParticipation
            ;
        }
      ) nodes;

      traversalParticipantNodeNames = sortedUnique (
        lib.filter (
          name: ((nodeSemantics.${name}.traversalParticipation.participates or false) == true)
        ) nodeNames
      );

      siteEgressIntent = {
        eligibleNodeNames = sortedUnique (siteUplinkCoreNames ++ (maybeOne upstreamSelectorNodeName));
        exitNodeNames = sortedUnique siteUplinkCoreNames;
        explicit = true;
        externalDomains = siteExternalDomains;
        uplinkCoreNodeNames = sortedUnique siteUplinkCoreNames;
        upstreamSelectorNodeName = upstreamSelectorNodeName;
      };

      forwardingSemantics = {
        coreNodeNames = coreNodeNames;
        explicit = true;
        nodes = nodeSemantics;
        policyNodeName = policyNodeName;
        traversalParticipantNodeNames = traversalParticipantNodeNames;
        upstreamSelectorNodeName = upstreamSelectorNodeName;
      };

      annotatedNodes = builtins.mapAttrs (name: node: node // (nodeSemantics.${name} or { })) nodes;
    in
    site
    // {
      coreNodeNames = coreNodeNames;
      policyNodeName = policyNodeName;
      upstreamSelectorNodeName = upstreamSelectorNodeName;
      uplinkCoreNames = siteUplinkCoreNames;
      uplinkNames = siteUplinkNames;
      egressIntent = siteEgressIntent;
      forwardingSemantics = forwardingSemantics;
      nodes = annotatedNodes;
    };

in
{
  inherit annotateSite;
  build = args: annotateSite args;
}
