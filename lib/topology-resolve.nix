{ lib }:

topoRaw:

let
  assert_ = cond: msg: if cond then true else throw msg;

  ulaPrefix =
    if topoRaw ? ulaPrefix && builtins.isString topoRaw.ulaPrefix then
      topoRaw.ulaPrefix
    else
      throw "topology-resolve: missing required topoRaw.ulaPrefix";

  tenantV4Base =
    if topoRaw ? tenantV4Base && builtins.isString topoRaw.tenantV4Base then
      topoRaw.tenantV4Base
    else
      throw "topology-resolve: missing required topoRaw.tenantV4Base";

  links = topoRaw.links or { };
  nodes0 = topoRaw.nodes or { };

  _nonEmptyLinks =
    assert_ (builtins.isAttrs links && (builtins.attrNames links) != [ ]) ''
      topology-resolve: rendered topology must contain at least one link
    '';

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
    if exact != null then
      exact
    else if byLink != null then
      byLink
    else
      bySemanticName;

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

  enforceWanContract =
    linkName: l:
    if (l.kind or null) != "wan" then
      true
    else
      let
        eps = endpointsOf l;
        epNames = builtins.attrNames eps;

        _two =
          assert_ (builtins.length epNames == 2) ''
            topology-resolve: WAN link must have exactly 2 endpoints

              link: ${linkName}
              endpoints: ${lib.concatStringsSep ", " epNames}
          '';

        unknown = lib.filter (n: !(nodes0 ? "${n}")) epNames;

        _known =
          assert_ (unknown == [ ]) ''
            topology-resolve: WAN link references unknown node(s)

              link: ${linkName}
              unknown: ${lib.concatStringsSep ", " unknown}
          '';
      in
      builtins.seq _two (builtins.seq _known true);

  _wanChecked =
    builtins.deepSeq
      (lib.forEach (builtins.attrNames links) (ln: enforceWanContract ln links.${ln}))
      true;

  maskOf =
    cidr:
    let
      parts = lib.splitString "/" (toString cidr);
    in
    if builtins.length parts == 2 then builtins.elemAt parts 1 else null;

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
    in
    {
      kind = l.kind or null;
      carrier = l.carrier or "lan";

      tenant = ep.tenant or null;
      gateway = ep.gateway or false;
      export = ep.export or false;

      addr4 = finalAddr4;
      addr6 = ep.addr6 or null;
      addr6Public = ep.addr6Public or null;

      ll6 = ep.ll6 or null;

      upstream = l.upstream or null;
      overlay = l.overlay or null;

      routes4 = ep.routes4 or [ ];
      routes6 = ep.routes6 or [ ];
      ra6Prefixes = ep.ra6Prefixes or [ ];

      acceptRA = ep.acceptRA or false;
      dhcp = finalDhcp;
    };

  linkNamesForNode =
    nodeName:
    let
      linkNamesSorted = lib.sort (a: b: a < b) (lib.attrNames links);
      hasAnyEndpoint = linkName: l: (chooseEndpointKey linkName l nodeName) != null;
    in
    lib.filter (
      lname:
      let
        l = links.${lname};
      in
      (lib.elem nodeName (membersOf l)) || (hasAnyEndpoint lname l)
    ) linkNamesSorted;

  interfacesForNode =
    nodeName:
    lib.listToAttrs (
      map (lname: {
        name = lname;
        value = mkIface lname links.${lname} nodeName;
      }) (linkNamesForNode nodeName)
    );

  endpointNodes = lib.unique (
    lib.concatMap (l: builtins.attrNames (l.endpoints or { })) (lib.attrValues links)
  );

  unknownEndpointNodes = lib.filter (n: !(nodes0 ? "${n}")) endpointNodes;

  _noUnknownEndpointNodes =
    assert_ (unknownEndpointNodes == [ ]) ''
      topology-resolve: link endpoints reference unknown node(s) (topology inference is disabled)

      unknown: ${lib.concatStringsSep ", " unknownEndpointNodes}
    '';

  stripLinuxSpecific =
    node:
    builtins.removeAttrs node [ "routingDomain" ];

  nodes' =
    lib.mapAttrs
      (n: node:
        (stripLinuxSpecific node)
        // {
          interfaces = interfacesForNode n;
        })
      nodes0;

  routing = import ./routing/static.nix { inherit lib; };

  topo1 =
    topoRaw
    // {
      inherit ulaPrefix tenantV4Base;
      nodes = nodes';
    };

in
builtins.seq _nonEmptyLinks
  (builtins.seq _wanChecked
    (builtins.seq _noUnknownEndpointNodes
      (routing.attach topo1)))
