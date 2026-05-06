{ lib, self ? { outPath = ./.; }, ... }:

topoRaw:

let
  helpers = import ./topology/resolve-helpers.nix { inherit lib self; };
  link = import ./topology/link-utils.nix { inherit lib self; };
  interfaceResolution = import ./topology/resolve/interfaces.nix { inherit lib self; };
  linkValidation = import ./topology/resolve/link-validation.nix { inherit lib self; };
  overlayResolution = import ./topology/resolve/overlays.nix { inherit lib self; };
  tenantOwnersMod = import ./routing/tenant-prefix-owners.nix { inherit lib self; };

  assert_ = cond: msg: if cond then true else throw msg;

  links = topoRaw.links or { };
  nodes0 = topoRaw.nodes or { };
  nodeNames = lib.sort (a: b: a < b) (builtins.attrNames nodes0);

  siteName = toString (topoRaw.siteName or "<unknown-site>");
  linkIdFor = linkName: "link::${siteName}::${toString linkName}";

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

  overlays = overlayResolution topoRaw;
  overlaysForNode = overlays.forNode;
  overlayReachability = overlays.reachability;

  _validatedLinks = linkValidation.validateLinks {
    inherit
      assert_
      linkMembersFor
      links
      nodeNames
      siteName
      ;
  };

  resolvedP2pPairs = linkValidation.resolvedP2pPairs {
    inherit linkMembersFor links;
  };

  # Allow multiple p2p links between the same node pair (lane-aware transit).
  # Uniqueness is enforced by linkName (attrset key) instead of pair membership.
  _p2pLinkMembershipValidated = builtins.deepSeq resolvedP2pPairs true;

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

  interfacesForNode =
    nodeName:
    interfaceResolution.forNode {
      inherit
        assert_
        linkMembersFor
        links
        nodeName
        overlayReachability
        overlaysForNode
        ;
      nodes = nodes0;
      mkLinkIface = mkIface;
    };

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
      id = linkIdFor linkName;
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

  tenantPrefixOwners = tenantOwnersMod.build topo1;

  topo2 = topo1 // {
    tenantPrefixOwners = tenantPrefixOwners;
  };

  resolveLoopbacks = import ./routing/resolve-loopbacks.nix { inherit lib self; };
  routingStatic = import ./routing/static.nix { inherit lib self; };

  topo3 = resolveLoopbacks.attach topo2;
  topo4 = routingStatic.attach topo3;

in
builtins.seq _validatedLinks (builtins.seq _p2pLinkMembershipValidated topo4)
