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

  # derive node names from roles
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

  # ---- IR helpers ----

  getP2PPool =
    siteKey: s:
    let
      # new compiler output uses:
      #   addressPools.p2p.{ipv4,ipv6}
      # legacy solver-internal / old compiler output used:
      #   transit.addressAuthority
      p =
        if s ? addressPools && builtins.isAttrs s.addressPools && s.addressPools ? p2p then
          s.addressPools.p2p
        else if s ? transit && builtins.isAttrs s.transit && s.transit ? addressAuthority then
          s.transit.addressAuthority
        else
          null;
    in
    requireAttr "${siteKey}.addressPools.p2p (or transit.addressAuthority)" p;

  # linearize transit.ordering if it is a single chain
  # returns null if it cannot be uniquely linearized
  linearizeOrdering =
    pairs:
    if pairs == null || !(builtins.isList pairs) || pairs == [ ] then
      null
    else
      let
        # normalize to { a, b } edges
        edges =
          lib.concatMap (
            p:
            if !(builtins.isList p) || builtins.length p != 2 then
              [ ]
            else
              let
                a = builtins.elemAt p 0;
                b = builtins.elemAt p 1;
              in
              [ { inherit a b; } ]
          ) pairs;

        nodes = lib.unique (lib.concatMap (e: [ e.a e.b ]) edges);

        outMap =
          builtins.foldl'
            (acc: e: acc // { "${e.a}" = (acc."${e.a}" or [ ]) ++ [ e.b ]; })
            { }
            edges;

        inMap =
          builtins.foldl'
            (acc: e: acc // { "${e.b}" = (acc."${e.b}" or [ ]) ++ [ e.a ]; })
            { }
            edges;

        outDeg = n: builtins.length (outMap."${n}" or [ ]);
        inDeg = n: builtins.length (inMap."${n}" or [ ]);

        starts = lib.filter (n: inDeg n == 0 && outDeg n == 1) nodes;
        ends = lib.filter (n: outDeg n == 0 && inDeg n == 1) nodes;

        uniqueStart = if builtins.length starts == 1 then builtins.head starts else null;
        uniqueEnd = if builtins.length ends == 1 then builtins.head ends else null;

        # each internal node must have in=1 out=1 for a pure chain
        isChainNode =
          n:
          if n == uniqueStart then (inDeg n == 0 && outDeg n == 1)
          else if n == uniqueEnd then (inDeg n == 1 && outDeg n == 0)
          else (inDeg n == 1 && outDeg n == 1);

        _shapeOk =
          uniqueStart != null
          && uniqueEnd != null
          && lib.all isChainNode nodes;

        # follow the chain
        follow =
          cur: seen:
          if cur == null || lib.elem cur seen then
            null
          else if cur == uniqueEnd then
            seen ++ [ cur ]
          else
            let
              nexts = outMap."${cur}" or [ ];
              next = if builtins.length nexts == 1 then builtins.head nexts else null;
            in
            if next == null then null else follow next (seen ++ [ cur ]);

        chain = if _shapeOk then follow uniqueStart [ ] else null;

        # ensure chain covers all nodes referenced by ordering
        coversAll =
          chain != null
          && builtins.length (lib.unique chain) == builtins.length (lib.unique nodes);
      in
      if coversAll then chain else null;

  # synthesize nodes from compiler IR deterministically
  mkNodesFromIR =
    siteKey: s:
    let
      ordering = s.transit.ordering or [ ];
      orderedUnits = lib.unique (lib.flatten ordering);

      attachments = s.attachment or [ ];
      accessUnits = lib.unique (map (a: a.unit) attachments);

      loopUnits =
        if s ? routerLoopbacks && builtins.isAttrs s.routerLoopbacks then
          builtins.attrNames s.routerLoopbacks
        else
          [ ];

      allUnits = lib.unique (orderedUnits ++ accessUnits ++ loopUnits);

      mk = name: role: { inherit role; };

      base = lib.listToAttrs (map (n: { name = n; value = { }; }) allUnits);

      chain = linearizeOrdering ordering;

      # roles from chain positions if possible; otherwise deterministic fallbacks.
      chainCore = if chain != null && builtins.length chain >= 1 then builtins.elemAt chain 0 else null;
      chainUpstream = if chain != null && builtins.length chain >= 2 then builtins.elemAt chain 1 else null;
      chainPolicy = if chain != null && builtins.length chain >= 3 then builtins.elemAt chain 2 else null;

      # deterministic fallbacks (prefer non-access nodes)
      nonAccess = lib.filter (n: !(lib.elem n accessUnits)) allUnits;

      fallbackCore = firstSorted "core node candidate" (if nonAccess != [ ] then nonAccess else allUnits);
      fallbackUpstream = firstSorted "upstream-selector node candidate" (if nonAccess != [ ] then nonAccess else allUnits);
      fallbackPolicy = firstSorted "policy node candidate" (if nonAccess != [ ] then nonAccess else allUnits);

      coreName = if chainCore != null && !(lib.elem chainCore accessUnits) then chainCore else fallbackCore;
      upstreamName =
        if chainUpstream != null && chainUpstream != coreName && !(lib.elem chainUpstream accessUnits) then
          chainUpstream
        else
          fallbackUpstream;
      policyName =
        if chainPolicy != null && chainPolicy != coreName && chainPolicy != upstreamName && !(lib.elem chainPolicy accessUnits) then
          chainPolicy
        else
          fallbackPolicy;

      withAccess =
        builtins.foldl'
          (acc: n: acc // { "${n}" = mk n "access"; })
          base
          accessUnits;

      withCore = withAccess // { "${coreName}" = mk coreName "core"; };
      withUpstream = withCore // { "${upstreamName}" = mk upstreamName "upstream-selector"; };
      withPolicy = withUpstream // { "${policyName}" = mk policyName "policy"; };

      # any remaining units not explicitly assigned but present in ordering become core (deterministic)
      remainingCores =
        lib.filter (n: !(lib.elem n (accessUnits ++ [ coreName upstreamName policyName ]))) orderedUnits;

      withRemainingCores =
        builtins.foldl'
          (acc: n: acc // { "${n}" = mk n "core"; })
          withPolicy
          (lib.sort (a: b: a < b) remainingCores);
    in
    withRemainingCores;

  solveOne =
    siteKey: s:
    let
      linkPairs = requireAttr "${siteKey}.transit.ordering" (s.transit.ordering or null);
      p2pPool = getP2PPool siteKey s;

      # derive nodes/anchors from ordering + attachment + routerLoopbacks
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

  routedSites0 = lib.mapAttrs solveOne sites;
  _all = inv.checkAll { sites = routedSites0; };
  routedSites = builtins.seq _all routedSites0;

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
