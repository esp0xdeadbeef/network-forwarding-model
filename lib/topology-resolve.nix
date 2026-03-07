{ lib }:

topoRaw:

let
  helpers = import ./topology/resolve-helpers.nix { inherit lib; };
  link = import ./topology/link-utils.nix { inherit lib; };

  assert_ = cond: msg: if cond then true else throw msg;

  links = topoRaw.links or { };
  nodes0 = topoRaw.nodes or { };
  nodeNames = lib.sort (a: b: a < b) (builtins.attrNames nodes0);

  _nodesAttrs = assert_ (builtins.isAttrs nodes0) "topology-resolve: topoRaw.nodes must be an attrset";

  linkMembersFor =
    linkName: l:
    link.resolvedMemberNodes {
      inherit linkName;
      link = l;
      inherit nodeNames;
    };

  getEpStrict =
    linkName: l: nodeName:
    link.getEpStrict {
      inherit linkName;
      link = l;
      inherit nodeName nodeNames;
    };

  validateLink =
    linkName:
    let
      l = links.${linkName};
      explicitMembers = l.members or [ ];
      endpointKeys = builtins.attrNames (link.endpointsOf l);

      _membersExist = lib.forEach explicitMembers (
        nodeName:
        assert_ (
          nodes0 ? "${nodeName}"
        ) "topology-resolve: link '${linkName}' references unknown member node '${nodeName}'"
      );

      _endpointsExist = lib.forEach endpointKeys (
        epKey:
        let
          _resolved = link.resolveEndpointNodeName {
            inherit linkName;
            link = l;
            inherit epKey nodeNames;
          };
        in
        true
      );

      finalMembers = linkMembersFor linkName l;

      _nonOrphan = assert_ (
        finalMembers != [ ]
      ) "topology-resolve: link '${linkName}' is orphaned (no valid members/endpoints)";
    in
    builtins.deepSeq _membersExist (builtins.deepSeq _endpointsExist (builtins.seq _nonOrphan true));

  _validatedLinks = builtins.deepSeq (lib.forEach (lib.sort (a: b: a < b) (
    builtins.attrNames links
  )) validateLink) true;

  mkIface =
    linkName: l: nodeName:
    let
      ep = getEpStrict linkName l nodeName;
      prebuilt = ep.interfaceData or null;
      generic = helpers.mkIfaceBase {
        inherit linkName;
        link = l;
        inherit ep;
      };
    in
    if prebuilt != null && builtins.isAttrs prebuilt then
      helpers.mergePrebuiltIface generic prebuilt
    else
      generic;

  linkNamesForNode =
    nodeName:
    let
      linkNamesSorted = lib.sort (a: b: a < b) (lib.attrNames links);
    in
    lib.filter (
      lname:
      let
        l = links.${lname};
      in
      (lib.elem nodeName (linkMembersFor lname l)) || ((link.chooseEndpointKey lname l nodeName) != null)
    ) linkNamesSorted;

  linkInterfacesForNode =
    nodeName:
    lib.listToAttrs (
      map (lname: {
        name = lname;
        value = mkIface lname links.${lname} nodeName;
      }) (linkNamesForNode nodeName)
    );

  logicalInterfacesForNode =
    nodeName:
    let
      node = nodes0.${nodeName} or { };
      nets = helpers.networksOf node;
      netNames = lib.sort (a: b: a < b) (builtins.attrNames nets);
    in
    lib.listToAttrs (
      map (
        netName:
        let
          ifName = helpers.logicalInterfaceNameFor netName;
        in
        {
          name = ifName;
          value = helpers.mkLogicalIface {
            inherit nodeName ifName netName;
            net = nets.${netName};
          };
        }
      ) netNames
    );

  interfacesForNode =
    nodeName:
    let
      linkInterfaces = linkInterfacesForNode nodeName;
      logicalInterfaces = logicalInterfacesForNode nodeName;
      clashes = lib.filter (n: linkInterfaces ? "${n}") (builtins.attrNames logicalInterfaces);

      _noIfaceClashes =
        assert_ (clashes == [ ])
          "topology-resolve: logical tenant interface(s) collide with link-backed interface(s) on node '${nodeName}': ${lib.concatStringsSep ", " clashes}";
    in
    builtins.seq _noIfaceClashes (linkInterfaces // logicalInterfaces);

  stripLinuxSpecific = node: builtins.removeAttrs node [ "routingDomain" ];

  nodes' = lib.mapAttrs (
    n: node: (stripLinuxSpecific node) // { interfaces = interfacesForNode n; }
  ) nodes0;

  normalizeLink =
    linkName: l:
    let
      members = linkMembersFor linkName l;

      normEndpoints = lib.listToAttrs (
        map (
          nodeName:
          let
            ep = getEpStrict linkName l nodeName;
          in
          {
            name = nodeName;
            value = ep // {
              node = nodeName;
              interface = linkName;
            };
          }
        ) members
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

  topo1 = topoRaw // {
    nodes = nodes';
    links = links';
  };

  resolveLoopbacks = import ./routing/resolve-loopbacks.nix { inherit lib; };
  routingStatic = import ./routing/static.nix { inherit lib; };

  topo2 = resolveLoopbacks.attach topo1;
  topo3 = routingStatic.attach topo2;

in
builtins.seq _validatedLinks topo3
