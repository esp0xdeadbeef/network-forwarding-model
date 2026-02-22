# ./default.nix
{ lib ? (import <nixpkgs> { }).lib }:

{ input }:

let
  # compiler output shape (confirmed):
  # { sites = { "<enterprise>.<site>" = { ... }; }; }
  sites =
    if input ? sites && builtins.isAttrs input.sites then
      input.sites
    else if builtins.isAttrs input then
      input
    else
      throw "network-solver: cannot locate sites in compiler output";

  allocP2P = import ./lib/p2p/alloc.nix { inherit lib; };
  inv = import ./lib/fabric/invariants/default.nix { inherit lib; };

  resolve = import ./lib/topology-resolve.nix { inherit lib; };

  assert_ = cond: msg: if cond then true else throw msg;

  requireAttr =
    path: v:
    if v == null then
      throw "network-solver: missing required attribute: ${path}"
    else
      v;

  # ---- parsing helpers (string-only; deterministic) ----

  split =
    sep: s:
    lib.splitString sep (toString s);

  take =
    n: xs:
    if builtins.length xs < n then xs else builtins.genList (i: builtins.elemAt xs i) n;

  join = sep: xs: lib.concatStringsSep sep xs;

  stripMask =
    cidr:
    let parts = split "/" cidr;
    in if parts == [ ] then toString cidr else builtins.elemAt parts 0;

  tenantV4BaseFrom =
    tenant4:
    let
      ip = stripMask tenant4;
      octs = split "." ip;
      _ok = assert_ (builtins.length octs == 4)
        "network-solver: cannot derive tenantV4Base from '${toString tenant4}' (expected IPv4 CIDR)";
    in
    builtins.seq _ok (join "." (take 2 octs));

  ulaPrefixFrom =
    tenant6:
    let
      ip = stripMask tenant6;
      hextets = split ":" ip;
      # expected something like fd42:dead:beef:10:: ...
      _ok = assert_ (builtins.length hextets >= 3)
        "network-solver: cannot derive ulaPrefix from '${toString tenant6}' (expected IPv6 CIDR with >= 3 hextets)";
    in
    builtins.seq _ok (join ":" (take 3 hextets));

  # derive node names from roles (no naming assumptions)
  nodeNamesByRole =
    role: nodes:
    builtins.attrNames (lib.filterAttrs (_: n: (n.role or null) == role) nodes);

  exactlyOne =
    what: xs:
    let
      _ = assert_ (builtins.length xs == 1)
        "network-solver: expected exactly one ${what}, got: ${lib.concatStringsSep ", " xs}";
    in
    builtins.head xs;

  firstSorted =
    what: xs:
    let
      _ = assert_ (xs != [ ]) "network-solver: expected at least one ${what}";
    in
    builtins.head (lib.sort (a: b: a < b) xs);

  # synthesize nodes from compiler IR
  mkNodesFromIR =
    siteKey: s:
    let
      cc = s.communicationContract or { };
      enf = cc.enforcement or { };
      auth = enf.authorityRoles or { };

      policyName = auth.internalRib or null;
      upstreamName = auth.externalRib or (enf.transitForwarder.sink or null);

      # units mentioned anywhere in ordering
      ordering = s.transit.ordering or [ ];
      orderedUnits = lib.unique (lib.flatten ordering);

      # access units from attachment[]
      attachments = s.attachment or [ ];
      accessUnits = lib.unique (map (a: a.unit) attachments);

      # heuristic: core candidates are ordered units minus explicitly named policy/upstream/access
      excluded =
        lib.unique (
          (lib.optional (policyName != null) policyName)
          ++ (lib.optional (upstreamName != null) upstreamName)
          ++ accessUnits
        );

      coreCandidates = lib.filter (n: !(lib.elem n excluded)) orderedUnits;

      mk = name: role: { inherit role; };

      base =
        lib.listToAttrs (map (n: { name = n; value = { }; }) (lib.unique (orderedUnits ++ accessUnits)));

      withRoles =
        base
        // (if policyName != null then { "${policyName}" = mk policyName "policy"; } else { })
        // (if upstreamName != null then { "${upstreamName}" = mk upstreamName "upstream-selector"; } else { });

      withAccess =
        builtins.foldl'
          (acc: n: acc // { "${n}" = mk n "access"; })
          withRoles
          accessUnits;

      # pick one or more cores; at least one required by invariants
      withCore =
        if coreCandidates == [ ] then
          # last resort: if nothing left, pick first from orderedUnits
          let c = firstSorted "core candidate (from transit.ordering)" orderedUnits;
          in withAccess // { "${c}" = mk c "core"; }
        else
          builtins.foldl'
            (acc: n: acc // { "${n}" = mk n "core"; })
            withAccess
            coreCandidates;
    in
    withCore;

  solveOne =
    siteKey: s:
    let
      # compiler IR (confirmed)
      p2pPool = s.transit.addressAuthority or null;
      linkPairs = s.transit.ordering or null;

      _pairsOk = requireAttr "${siteKey}.transit.ordering" linkPairs;
      _poolOk  = requireAttr "${siteKey}.transit.addressAuthority" p2pPool;

      # derive nodes/anchors from enforcement + ordering + attachment
      nodes = mkNodesFromIR siteKey s;

      # derive ulaPrefix + tenantV4Base from tenant domains
      tenants = (s.domains.tenants or [ ]);
      _tenOk = assert_ (tenants != [ ]) "network-solver: site '${siteKey}' has no domains.tenants; cannot derive prefixes";

      firstTenant = builtins.head tenants;

      tenantV4Base = tenantV4BaseFrom (requireAttr "${siteKey}.domains.tenants[0].ipv4" (firstTenant.ipv4 or null));
      ulaPrefix = ulaPrefixFrom (requireAttr "${siteKey}.domains.tenants[0].ipv6" (firstTenant.ipv6 or null));

      policyNode = exactlyOne "policy node (role=policy)" (nodeNamesByRole "policy" nodes);
      upstreamNode = exactlyOne "upstream-selector node (role=upstream-selector)" (nodeNamesByRole "upstream-selector" nodes);
      coreNode = firstSorted "core node (role=core)" (nodeNamesByRole "core" nodes);

      siteForAlloc = {
        siteName = s.id or siteKey;
        links = linkPairs;
        linkPairs = linkPairs;
        p2p-pool = p2pPool;

        inherit nodes;

        # keep compiler IR around for alloc's collision skipping with tenants
        domains = s.domains or null;
      };

      p2pLinks = allocP2P.alloc { site = siteForAlloc; };

      topoRaw = {
        siteName = s.id or siteKey;

        inherit
          ulaPrefix
          tenantV4Base
          nodes
          ;

        coreNodeName = coreNode;
        policyNodeName = policyNode;
        upstreamSelectorNodeName = upstreamNode;

        links = p2pLinks;

        compilerIR = s;
      };

      topoResolved = resolve topoRaw;

      _ = inv.checkSite { site = topoResolved; };
    in
    topoResolved;

  _all = inv.checkAll { inherit sites; };

  routedSites = builtins.seq _all (lib.mapAttrs solveOne sites);

  siteOrThrow =
    let ks = builtins.attrNames routedSites;
    in
    if builtins.length ks == 1 then
      routedSites.${builtins.head ks}
    else
      throw "network-solver: expected exactly one site in input, got: ${lib.concatStringsSep ", " ks}";

in
{
  sites = routedSites;
  site = siteOrThrow;
}
