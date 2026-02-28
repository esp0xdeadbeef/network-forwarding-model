{ lib }:
{ enterprise, siteId, site }:

let
  utils = import ../util { inherit lib; };
  derive = import ../util/derive.nix { inherit lib; };
  allocP2P = import ../../lib/p2p/alloc.nix { inherit lib; };
  resolve = import ../../lib/topology-resolve.nix { inherit lib; };
  addr = import ../../lib/model/addressing.nix { inherit lib; };

  _ = if builtins.isAttrs site then true else throw "network-solver: sites.${enterprise}.${siteId} must be an attrset";

  ordering =
    utils.requireAttr "sites.${enterprise}.${siteId}.transit.ordering" (site.transit.ordering or null);

  p2pPool =
    utils.requireAttr "sites.${enterprise}.${siteId}.addressPools.p2p" (site.addressPools.p2p or null);

  localPool =
    utils.requireAttr "sites.${enterprise}.${siteId}.addressPools.local" (site.addressPools.local or null);

  stripMask =
    cidr:
    let
      parts = lib.splitString "/" (toString cidr);
    in
    if builtins.length parts == 0 then toString cidr else builtins.elemAt parts 0;

  attachments = site.attachment or [ ];
  accessUnits = lib.unique (map (a: a.unit) attachments);

  orderedUnits =
    lib.unique (lib.concatMap
      (p:
        if builtins.isList p && builtins.length p == 2
           && builtins.isString (builtins.elemAt p 0)
           && builtins.isString (builtins.elemAt p 1)
        then [ (builtins.elemAt p 0) (builtins.elemAt p 1) ]
        else throw "network-solver: sites.${enterprise}.${siteId}.transit.ordering must contain 2-element string pairs")
      ordering);

  loopUnits = if site ? routerLoopbacks then builtins.attrNames site.routerLoopbacks else [ ];

  allUnits = lib.unique (orderedUnits ++ accessUnits ++ loopUnits);
  _unitsOk = if allUnits != [ ] then true else throw "network-solver: no router units found";

  # -------- Stable role mapping (NO substring inference) --------
  orderingEdges =
    map (p: { a = builtins.elemAt p 0; b = builtins.elemAt p 1; })
      (lib.filter (p: builtins.isList p && builtins.length p == 2) ordering);

  uniq = xs: lib.unique xs;

  nodesInOrdering = uniq (lib.concatMap (e: [ e.a e.b ]) orderingEdges);

  countIn = n: xs: builtins.length (lib.filter (x: x == n) xs);

  indeg = n: countIn n (map (e: e.b) orderingEdges);
  outdeg = n: countIn n (map (e: e.a) orderingEdges);

  nextOf =
    n:
    let
      outs = lib.filter (e: e.a == n) orderingEdges;
    in
      if outs == [ ] then null
      else if builtins.length outs == 1 then (builtins.elemAt outs 0).b
      else throw "network-solver: transit.ordering must not branch from '${n}' (multiple outgoing edges)";

  coreByOrdering =
    let
      roots = lib.filter (n: indeg n == 0) nodesInOrdering;
    in
      if roots == [ ] then null
      else lib.head (lib.sort (a: b: a < b) roots);

  accessByOrdering =
    let
      sinks = lib.filter (n: outdeg n == 0) nodesInOrdering;
      sinksSorted = lib.sort (a: b: a < b) sinks;
      attached = lib.filter (n: lib.elem n accessUnits) sinksSorted;
    in
      if accessUnits != [ ] then
        (if attached != [ ] then lib.head attached else (if sinksSorted == [ ] then null else lib.head sinksSorted))
      else
        (if sinksSorted == [ ] then null else lib.head sinksSorted);

  chain =
    let
      start = coreByOrdering;
      go = seen: cur:
        if cur == null then seen
        else if lib.elem cur seen then throw "network-solver: transit.ordering contains a cycle at '${cur}'"
        else go (seen ++ [ cur ]) (nextOf cur);
    in
      if start == null then [ ] else go [ ] start;

  inferredRolesFromOrdering =
    let
      len = builtins.length chain;
      at = i: builtins.elemAt chain i;
      base =
        if len == 4 then {
          "${at 0}" = "core";
          "${at 1}" = "upstream-selector";
          "${at 2}" = "policy";
          "${at 3}" = "access";
        } else if len == 3 then {
          "${at 0}" = "core";
          "${at 1}" = "policy";
          "${at 2}" = "access";
        } else if len == 2 then {
          "${at 0}" = "core";
          "${at 1}" = "access";
        } else
          { };
      withAccess =
        builtins.foldl'
          (acc: u: acc // { "${toString u}" = "access"; })
          base
          accessUnits;
    in
      withAccess;

  roleFromInput =
    unit:
    let
      n = toString unit;

      fromNodes =
        if site ? nodes && builtins.isAttrs site.nodes && site.nodes ? "${n}"
        then (site.nodes.${n}.role or null)
        else null;

      fromTopology =
        if site ? topology && builtins.isAttrs site.topology
           && site.topology ? nodes && builtins.isAttrs site.topology.nodes
           && site.topology.nodes ? "${n}"
        then
          let v = site.topology.nodes.${n};
          in if builtins.isAttrs v then (v.role or null) else null
        else null;

      fromUnits =
        if site ? units && builtins.isAttrs site.units && site.units ? "${n}"
        then (site.units.${n}.role or null)
        else null;

      fromUnitRoles =
        if site ? unitRoles && builtins.isAttrs site.unitRoles && site.unitRoles ? "${n}"
        then (site.unitRoles.${n} or null)
        else null;

      inferred =
        if inferredRolesFromOrdering ? "${n}" then inferredRolesFromOrdering.${n} else null;

    in
      if fromNodes != null then fromNodes
      else if fromTopology != null then fromTopology
      else if fromUnits != null then fromUnits
      else if fromUnitRoles != null then fromUnitRoles
      else inferred;

  missingRoles = lib.filter (u: roleFromInput u == null) allUnits;

  _rolesOk =
    if missingRoles == [ ] then true else
    throw ''
      network-solver: missing required unit role(s) from compiler IR (and cannot infer from transit.ordering)

      site: ${enterprise}.${siteId}
      units missing roles: ${lib.concatStringsSep ", " (map toString missingRoles)}

      Provide explicit roles via one of:
      - sites.<ent>.<site>.nodes.<unit>.role
      - sites.<ent>.<site>.topology.nodes.<unit>.role
      - sites.<ent>.<site>.units.<unit>.role
      - sites.<ent>.<site>.unitRoles.<unit> = "<role>"
    '';

  nodes =
    lib.listToAttrs (map (n:
      let
        unit = toString n;
        unitInfo =
          if site ? units && builtins.isAttrs site.units && site.units ? "${unit}" && builtins.isAttrs site.units.${unit}
          then site.units.${unit}
          else { };

        isolated = unitInfo.isolated or false;
        containers = unitInfo.containers or (if isolated then [ "isolated-0" ] else [ "default" ]);

        routingDomain =
          if isolated then
            "vrf-${unit}-isolated"
          else
            "vrf-default";
      in
      {
        name = unit;
        value = {
          role = roleFromInput unit;
          inherit isolated containers routingDomain;
        };
      }) allUnits);

  domains = site.domains or { };
  tenants =
    if domains ? tenants && builtins.isList domains.tenants
    then domains.tenants
    else [ ];

  deriveTenantV4Bases =
    map (t: derive.tenantV4BaseFrom t.ipv4) (lib.filter (t: builtins.isAttrs t && t ? ipv4) tenants);

  deriveUlaPrefixes =
    map (t: derive.ulaPrefixFrom t.ipv6) (lib.filter (t: builtins.isAttrs t && t ? ipv6) tenants);

  v4Bases = uniq deriveTenantV4Bases;
  ulaBases = uniq deriveUlaPrefixes;

  tenantV4Base =
    if site ? tenantV4Base && builtins.isString site.tenantV4Base then
      site.tenantV4Base
    else if v4Bases == [ ] then
      throw "network-solver: cannot derive tenantV4Base (no tenants with ipv4); provide sites.${enterprise}.${siteId}.tenantV4Base"
    else if builtins.length v4Bases == 1 then
      builtins.elemAt v4Bases 0
    else
      throw "network-solver: inconsistent tenantV4Base across tenants: ${lib.concatStringsSep ", " v4Bases}";

  ulaPrefix =
    if site ? ulaPrefix && builtins.isString site.ulaPrefix then
      site.ulaPrefix
    else if ulaBases == [ ] then
      throw "network-solver: cannot derive ulaPrefix (no tenants with ipv6); provide sites.${enterprise}.${siteId}.ulaPrefix"
    else if builtins.length ulaBases == 1 then
      builtins.elemAt ulaBases 0
    else
      throw "network-solver: inconsistent ulaPrefix across tenants: ${lib.concatStringsSep ", " ulaBases}";

  siteForAlloc = {
    siteName = siteId;
    links = ordering;
    linkPairs = ordering;
    p2p-pool = p2pPool;
    inherit nodes;
    inherit domains;
  };

  p2pLinks = allocP2P.alloc { site = siteForAlloc; };

  coreUnits = lib.filter (u: (roleFromInput u) == "core") allUnits;

  coreUnit =
    if coreUnits == [ ] then
      throw "network-solver: expected at least one unit with role='core'"
    else
      builtins.elemAt (lib.sort (a: b: toString a < toString b) coreUnits) 0;

  upstreamList =
    if site ? upstreams && builtins.isAttrs site.upstreams
       && site.upstreams ? cores && builtins.isAttrs site.upstreams.cores
       && site.upstreams.cores ? "${toString coreUnit}"
    then (site.upstreams.cores.${toString coreUnit} or [ ])
    else [ ];

  mkWanAddr4 =
    idx:
    let
      base = "${stripMask localPool.ipv4}/32";
    in
    addr.hostCidr (100 + idx) base;

  mkWanAddr6 =
    idx:
    let
      base = "${stripMask localPool.ipv6}/128";
    in
    addr.hostCidr (100 + idx) base;

  mkWanLL6 =
    idx:
    addr.hostCidr (idx + 1) "fe80::/128";

  mkWanLink =
    idx: u:
    let
      nm = if builtins.isAttrs u && u ? name then toString u.name else toString u;
      linkName = "wan-${toString coreUnit}-${nm}";
      isOverlay =
        (builtins.isAttrs u && u ? kind && (toString u.kind) == "overlay")
        || (builtins.isAttrs u && u ? peerSite)
        || (builtins.isAttrs u && u ? mustTraverse)
        || (builtins.isAttrs u && u ? terminateOn);

      ovMeta =
        if isOverlay then {
          kind = "overlay";
          name = nm;
          peerSite = u.peerSite or null;
          mustTraverse = u.mustTraverse or [ ];
          terminateOn = u.terminateOn or null;
        } else null;

      a4 = if localPool ? ipv4 then mkWanAddr4 idx else null;
      a6 = if localPool ? ipv6 then mkWanAddr6 idx else null;
      ll6 = mkWanLL6 idx;
    in
    {
      name = linkName;
      value = {
        kind = "wan";
        carrier = "wan";
        overlay = ovMeta;
        upstream = nm;
        endpoints = {
          "${toString coreUnit}" = {
            gateway = true;
            export = true;
            addr4 = a4;
            addr6 = a6;
            ll6 = ll6;
          };
        };
      };
    };

  wanLinks = lib.listToAttrs (lib.imap0 mkWanLink upstreamList);

  links = p2pLinks // wanLinks;

  communication = site.communicationContract or { };
  nat0 = communication.nat or { };
  natIngress = nat0.ingress or [ ];

  natMode =
    if (nat0.enabled or false) == true then
      "custom"
    else if builtins.length natIngress > 0 then
      "custom"
    else
      "none";

  natRealized = {
    mode = natMode;
    owner = toString coreUnit;
    ingress = natIngress;
  };

  ruleKey =
    r:
    let
      p = toString (r.source.priority or 0);
      i = toString (r.source.index or 0);
      id = toString (r.source.id or r.id or "");
    in
    "${zpad 10 p}|${zpad 10 i}|${id}";

  zpad =
    w: s:
    let
      len = builtins.stringLength s;
      zeros = builtins.concatStringsSep "" (builtins.genList (_: "0") (lib.max 0 (w - len)));
    in
    zeros + s;

  enforcementRules =
    let
      rs0 = communication.allowedRelations or [ ];
      rs1 = lib.filter builtins.isAttrs rs0;
    in
    lib.sort (a: b: ruleKey a < ruleKey b) rs1;

  traversal = {
    mode = "ordering-chain";
    chain = chain;
    edges = orderingEdges;
    inferred = inferredRolesFromOrdering;
    accessUnitHint = accessByOrdering;
    coreUnitHint = coreByOrdering;
  };

  # Keep a compact per-site debug snapshot without polluting runtime fields.
  compilerIRDebug = builtins.removeAttrs site [ "id" "enterprise" ];

  topoRaw = {
    siteName = siteId;
    inherit tenantV4Base ulaPrefix;
    inherit nodes;
    inherit links;
    inherit domains;

    _nat = natRealized;
    _enforcement = {
      owner =
        let
          policies = lib.filter (u: (roleFromInput u) == "policy") allUnits;
        in
        if policies == [ ] then null else lib.head (lib.sort (a: b: toString a < toString b) policies);
      rules = enforcementRules;
    };
    _traversal = traversal;
  };

  topoResolved = resolve topoRaw;

  cleaned =
    builtins.removeAttrs topoResolved [
      "id"
      "enterprise"
      "siteName"
      "tenantV4Base"
      "ulaPrefix"
    ];

  withVerification =
    cleaned
    // {
      _debug = (cleaned._debug or { }) // {
        compilerIR = compilerIRDebug; # TODO DONE: Move `compilerIR` out of runtime fields
      };

      _verification = (cleaned._verification or { }) // {
        solver = {
          nat = natRealized;
          traversal = traversal;
        };
      };
    };

in
  builtins.seq _unitsOk (builtins.seq _rolesOk withVerification)
