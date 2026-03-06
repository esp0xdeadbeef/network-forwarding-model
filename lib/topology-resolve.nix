{ lib }:

topoRaw:

let
  assert_ = cond: msg: if cond then true else throw msg;

  links = topoRaw.links or { };
  nodes0 = topoRaw.nodes or { };

  _nodesAttrs =
    assert_ (builtins.isAttrs nodes0) "topology-resolve: topoRaw.nodes must be an attrset";

  membersOf = l: lib.unique ((l.members or [ ]) ++ (builtins.attrNames (l.endpoints or { })));
  endpointsOf = l: l.endpoints or { };

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

  maskOf =
    cidr:
    let
      parts = lib.splitString "/" (toString cidr);
    in
    if builtins.length parts == 2 then builtins.elemAt parts 1 else null;

  mkConnectedRoute = dst: { inherit dst; proto = "connected"; };

  mkIface =
    linkName: l: nodeName:
    let
      ep = getEp linkName l nodeName;

      rawAddr4 = ep.addr4 or null;
      m4 = if rawAddr4 != null then maskOf rawAddr4 else null;

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
    in
    {
      link = linkName;
      kind = l.kind or null;
      type = l.type or (l.kind or null);
      carrier = l.carrier or "lan";

      tenant = ep.tenant or null;
      gateway = ep.gateway or false;
      export = ep.export or false;

      addr4 = finalAddr4;
      addr6 = rawAddr6;
      addr6Public = rawAddr6Public;

      ll6 = ep.ll6 or null;

      uplink = ep.uplink or l.uplink or l.upstream or null;
      upstream = l.upstream or ep.uplink or null;
      overlay = l.overlay or null;

      routes4 = connected4 ++ (ep.routes4 or [ ]);
      routes6 = connected6 ++ (ep.routes6 or [ ]);
      ra6Prefixes = ra6;

      acceptRA = ep.acceptRA or false;
      dhcp = finalDhcp;
    };

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
      members = membersOf l;

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
topo3
