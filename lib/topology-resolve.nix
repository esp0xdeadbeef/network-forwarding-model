{ lib }:

topoRaw:

let
  cidr = import ./fabric/invariants/cidr-utils.nix { inherit lib; };

  assert_ = cond: msg: if cond then true else throw msg;

  links = topoRaw.links or { };
  nodes0 = topoRaw.nodes or { };
  nodeNames = lib.sort (a: b: a < b) (builtins.attrNames nodes0);

  _nodesAttrs =
    assert_ (builtins.isAttrs nodes0) "topology-resolve: topoRaw.nodes must be an attrset";

  membersOf = l: lib.unique ((l.members or [ ]) ++ (builtins.attrNames (l.endpoints or { })));
  endpointsOf = l: l.endpoints or { };

  resolveEndpointNodeName =
    linkName: l: epKey:
    let
      candidates =
        lib.filter
          (nodeName:
            epKey == nodeName
            || epKey == "${nodeName}-${linkName}"
            || (
              let
                nm = l.name or null;
              in
              nm != null && epKey == "${nodeName}-${nm}"
            ))
          nodeNames;
    in
    if builtins.length candidates == 1 then
      builtins.elemAt candidates 0
    else if builtins.length candidates == 0 then
      throw "topology-resolve: endpoint '${epKey}' on link '${linkName}' does not reference a valid node"
    else
      throw "topology-resolve: endpoint '${epKey}' on link '${linkName}' is ambiguous across nodes: ${lib.concatStringsSep ", " candidates}";

  validateLink =
    linkName:
    let
      l = links.${linkName};
      explicitMembers = l.members or [ ];
      endpointKeys = builtins.attrNames (endpointsOf l);

      _membersExist =
        lib.forEach explicitMembers (
          nodeName:
          assert_
            (nodes0 ? "${nodeName}")
            "topology-resolve: link '${linkName}' references unknown member node '${nodeName}'"
        );

      _endpointsExist =
        lib.forEach endpointKeys (
          epKey:
          let
            _resolved = resolveEndpointNodeName linkName l epKey;
          in
          true
        );

      resolvedEndpointNodes = map (epKey: resolveEndpointNodeName linkName l epKey) endpointKeys;

      finalMembers = lib.unique (explicitMembers ++ resolvedEndpointNodes);

      _nonOrphan =
        assert_
          (finalMembers != [ ])
          "topology-resolve: link '${linkName}' is orphaned (no valid members/endpoints)"
        ;
    in
    builtins.deepSeq _membersExist (builtins.deepSeq _endpointsExist (builtins.seq _nonOrphan true));

  _validatedLinks =
    builtins.deepSeq (lib.forEach (lib.sort (a: b: a < b) (builtins.attrNames links)) validateLink) true;

  chooseEndpointKey =
    linkName: l: nodeName:
    let
      eps = endpointsOf l;
      exact = if eps ? "${nodeName}" then nodeName else null;

      byLinkName = "${nodeName}-${linkName}";
      byLink = if eps ? "${byLinkName}" then byLinkName else null;

      bySemanticName =
        let
          nm = l.name or null;
          k = if nm == null then null else "${nodeName}-${nm}";
        in
        if k != null && eps ? "${k}" then k else null;
    in
    if exact != null then exact else if byLink != null then byLink else bySemanticName;

  getEp =
    linkName: l: nodeName:
    let
      eps = endpointsOf l;
      k = chooseEndpointKey linkName l nodeName;
      isMember = lib.elem nodeName (membersOf l);
    in
    if k != null then
      eps.${k} or { }
    else if isMember then
      throw "topology-resolve: missing endpoint for member '${nodeName}' on link '${linkName}'"
    else
      { };

  splitCidr =
    cidrStr:
    let
      parts = lib.splitString "/" (toString cidrStr);
    in
    if builtins.length parts != 2 then
      throw "topology-resolve: invalid CIDR '${toString cidrStr}'"
    else
      {
        ip = builtins.elemAt parts 0;
        prefix = lib.toInt (builtins.elemAt parts 1);
      };

  intToV4 =
    n:
    let
      o0 = builtins.div n (256 * 256 * 256);
      r0 = n - o0 * (256 * 256 * 256);
      o1 = builtins.div r0 (256 * 256);
      r1 = r0 - o1 * (256 * 256);
      o2 = builtins.div r1 256;
      o3 = r1 - o2 * 256;
    in
    lib.concatStringsSep "." (map toString [ o0 o1 o2 o3 ]);

  canonicalCidr =
    cidrStr:
    let
      c = splitCidr cidrStr;
      r = cidr.cidrRange cidrStr;
      base =
        if r.family == 4 then
          intToV4 r.start
        else
          toString r.start;
    in
    "${base}/${toString c.prefix}";

  mkConnectedRoute = dst: {
    dst = canonicalCidr dst;
    proto = "connected";
  };

  mkIface =
    linkName: l: nodeName:
    let
      ep = getEp linkName l nodeName;
      prebuilt = ep.interfaceData or null;

      rawAddr4 = ep.addr4 or null;
      m4 =
        if rawAddr4 != null then
          let
            parts = lib.splitString "/" (toString rawAddr4);
          in
          if builtins.length parts == 2 then builtins.elemAt parts 1 else null
        else
          null;

      useDhcp =
        rawAddr4 != null
        && m4 != null
        && m4 != "0"
        && m4 != "31";

      finalAddr4 = if useDhcp then null else rawAddr4;
      finalDhcp = if useDhcp then true else (ep.dhcp or false);

      rawAddr6 = ep.addr6 or null;
      rawAddr6Public = ep.addr6Public or null;

      ra6 = ep.ra6Prefixes or [ ];

      connected4 =
        if finalAddr4 == null then [ ] else [ (mkConnectedRoute finalAddr4) ];

      connected6 =
        (lib.optional (rawAddr6 != null) (mkConnectedRoute rawAddr6))
        ++ (lib.optional (rawAddr6Public != null) (mkConnectedRoute rawAddr6Public))
        ++ (map mkConnectedRoute ra6);

      generic = {
        link = linkName;
        kind = l.kind or null;
        type = l.type or (l.kind or null);
        carrier = l.carrier or "lan";

        tenant = ep.tenant or null;
        gateway = ep.gateway or false;

        addr4 = finalAddr4;
        peerAddr4 = ep.peerAddr4 or null;
        addr6 = rawAddr6;
        peerAddr6 = ep.peerAddr6 or null;
        addr6Public = rawAddr6Public;

        ll6 = ep.ll6 or null;

        uplink = ep.uplink or l.uplink or l.upstream or null;
        upstream = l.upstream or ep.uplink or null;
        overlay = l.overlay or null;

        routes = {
          ipv4 = connected4 ++ (ep.routes4 or [ ]);
          ipv6 = connected6 ++ (ep.routes6 or [ ]);
        };
        ra6Prefixes = ra6;

        acceptRA = ep.acceptRA or false;
        dhcp = finalDhcp;
      };
    in
    if prebuilt != null && builtins.isAttrs prebuilt then
      generic
      // prebuilt
      // {
        link = linkName;
        kind = prebuilt.kind or generic.kind;
        type = prebuilt.type or generic.type;
        carrier = prebuilt.carrier or generic.carrier;
        routes =
          if prebuilt ? routes && builtins.isAttrs prebuilt.routes then
            {
              ipv4 = prebuilt.routes.ipv4 or [ ];
              ipv6 = prebuilt.routes.ipv6 or [ ];
            }
          else
            generic.routes;
      }
    else
      generic;

  linkNamesForNode =
    nodeName:
    let
      linkNamesSorted = lib.sort (a: b: a < b) (lib.attrNames links);
    in
    lib.filter
      (lname:
        let
          l = links.${lname};
        in
        (lib.elem nodeName (membersOf l)) || ((chooseEndpointKey lname l nodeName) != null))
      linkNamesSorted;

  interfacesForNode =
    nodeName:
    lib.listToAttrs (
      map
        (lname: {
          name = lname;
          value = mkIface lname links.${lname} nodeName;
        })
        (linkNamesForNode nodeName)
    );

  stripLinuxSpecific = node: builtins.removeAttrs node [ "routingDomain" ];

  nodes' =
    lib.mapAttrs
      (n: node:
        (stripLinuxSpecific node) // { interfaces = interfacesForNode n; })
      nodes0;

  normalizeLink =
    linkName: l:
    let
      explicitMembers = l.members or [ ];
      endpointKeys = builtins.attrNames (endpointsOf l);
      resolvedEndpointNodes = map (epKey: resolveEndpointNodeName linkName l epKey) endpointKeys;
      members = lib.unique (explicitMembers ++ resolvedEndpointNodes);

      normEndpoints =
        lib.listToAttrs (
          map
            (nodeName:
              let
                ep = getEp linkName l nodeName;
              in
              {
                name = nodeName;
                value =
                  ep
                  // {
                    node = nodeName;
                    interface = linkName;
                  };
              })
            members
        );
    in
    l
    // {
      kind = l.kind or null;
      type = l.type or (l.kind or null);
      members = members;
      endpoints = normEndpoints;
    };

  links' = lib.mapAttrs normalizeLink links;

  topo1 =
    topoRaw
    // {
      nodes = nodes';
      links = links';
    };

  resolveLoopbacks = import ./routing/resolve-loopbacks.nix { inherit lib; };
  routingStatic = import ./routing/static.nix { inherit lib; };

  topo2 = resolveLoopbacks.attach topo1;
  topo3 = routingStatic.attach topo2;

in
builtins.seq _validatedLinks topo3
