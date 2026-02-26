# ./lib/routing/static.nix
{ lib }:

let
  stripMask =
    s:
    let
      parts = lib.splitString "/" (toString s);
    in
    if builtins.length parts == 0 then toString s else builtins.elemAt parts 0;

  membersOf = l: lib.unique ((l.members or [ ]) ++ (builtins.attrNames (l.endpoints or { })));
  endpointsOf = l: l.endpoints or { };

  chooseEndpointKey =
    linkName: l: nodeName:
    let
      eps = endpointsOf l;
      keys = builtins.attrNames eps;

      exact = if eps ? "${nodeName}" then nodeName else null;

      byLinkName = "${nodeName}-${linkName}";
      byLink = if eps ? "${byLinkName}" then byLinkName else null;

      bySemanticName =
        let
          nm = l.name or null;
          k = if nm == null then null else "${nodeName}-${nm}";
        in
        if k != null && eps ? "${k}" then k else null;

      parts = lib.splitString "-" nodeName;
      lastPart = if parts == [ ] then "" else lib.last parts;

      hasNumericSuffix = builtins.match "^[0-9]+$" lastPart != null;

      baseName =
        if hasNumericSuffix && (lib.length parts) > 1 then
          lib.concatStringsSep "-" (lib.init parts)
        else
          null;

      byBaseSuffix = if baseName != null && eps ? "${baseName}" then baseName else null;

      pref = "${nodeName}-";
      prefKeys = lib.filter (k: lib.hasPrefix pref k) keys;

      bySinglePrefix = if lib.length prefKeys == 1 then lib.head prefKeys else null;

      bySortedPrefix = if prefKeys == [ ] then null else lib.head (lib.sort (a: b: a < b) prefKeys);
    in
    if exact != null then
      exact
    else if byLink != null then
      byLink
    else if bySemanticName != null then
      bySemanticName
    else if byBaseSuffix != null then
      byBaseSuffix
    else if bySinglePrefix != null then
      bySinglePrefix
    else
      bySortedPrefix;

  getEp =
    linkName: l: nodeName:
    let
      k = chooseEndpointKey linkName l nodeName;
      eps = endpointsOf l;
    in
    if k == null then { } else (eps.${k} or { });

  findLinkBetween =
    { links, from, to }:
    let
      names = builtins.attrNames links;

      hits =
        lib.filter (
          lname:
          let
            l = links.${lname};
            m = membersOf l;
          in
          lib.elem from m && lib.elem to m
        ) names;
    in
    if hits == [ ] then null else lib.head (lib.sort (a: b: a < b) hits);

  nextHop =
    { links, from, to }:
    let
      lname = findLinkBetween { inherit links from to; };
      l = if lname == null then null else links.${lname};
      epTo = if l == null then { } else getEp lname l to;
    in
    {
      linkName = lname;
      via4 = if epTo ? addr4 && epTo.addr4 != null then stripMask epTo.addr4 else null;
      via6 = if epTo ? addr6 && epTo.addr6 != null then stripMask epTo.addr6 else null;
    };

  mkRoute4 = dst: via4: { inherit dst via4; };
  mkRoute6 = dst: via6: { inherit dst via6; };

  default4 = "0.0.0.0/0";
  default6 = "::/0";

  tenantRanges4 = topo: map (t: t.ipv4) (topo.compilerIR.domains.tenants or [ ]);
  tenantRanges6 = topo: map (t: t.ipv6) (topo.compilerIR.domains.tenants or [ ]);

  assert_ = cond: msg: if cond then true else throw msg;

  exactlyOne =
    what: xs:
    let
      _ = assert_ (builtins.length xs == 1)
        "routing(static): expected exactly one ${what}, got: ${lib.concatStringsSep ", " xs}";
    in
    builtins.head xs;

  roleNames =
    topo: role:
    builtins.attrNames (lib.filterAttrs (_: n: (n.role or null) == role) (topo.nodes or { }));

  requireHop =
    { from, to, hop, fam }:
    let
      _linkOk = assert_ (hop.linkName != null)
        "routing(static): missing p2p link between '${from}' and '${to}' (needed for IPv${toString fam})";
      _viaOk =
        assert_ (
          (if fam == 4 then hop.via4 else hop.via6) != null
        )
        "routing(static): missing next-hop address (IPv${toString fam}) on '${to}' for link '${hop.linkName}' (from '${from}')";
    in
    builtins.seq _linkOk _viaOk;

  roleOf = topo: nodeName: (topo.nodes.${nodeName}.role or null);

in
{
  attach =
    topo:
    let
      links = topo.links or { };
      nodes0 = topo.nodes or { };

      policyNode =
        if topo ? policyNodeName && topo.policyNodeName != null then
          topo.policyNodeName
        else
          exactlyOne "policy node" (roleNames topo "policy");

      upstreamNode =
        if topo ? upstreamSelectorNodeName && topo.upstreamSelectorNodeName != null then
          topo.upstreamSelectorNodeName
        else
          exactlyOne "upstream-selector node" (roleNames topo "upstream-selector");

      coreNode =
        if topo ? coreNodeName && topo.coreNodeName != null then
          topo.coreNodeName
        else
          exactlyOne "core node" (roleNames topo "core");

      accessNode =
        exactlyOne "access node (static routing mode requires one)" (roleNames topo "access");

      t4 = tenantRanges4 topo;
      t6 = tenantRanges6 topo;

      setIfaceRoutes =
        node: linkName: routes4: routes6:
        if linkName == null then
          node
        else
          let
            ifs = node.interfaces or { };
            cur = ifs.${linkName} or null;
          in
          if cur == null then
            node
          else
            node
            // {
              interfaces =
                ifs
                // {
                  "${linkName}" =
                    cur
                    // {
                      routes4 = routes4;
                      routes6 = routes6;
                    };
                };
            };

      mkNodeRoutes =
        nodeName:
        let
          role = roleOf topo nodeName;

          nhToAccess =
            if nodeName == accessNode then
              { linkName = null; via4 = null; via6 = null; }
            else
              nextHop { inherit links; from = nodeName; to = accessNode; };

          nhToPolicy =
            if nodeName == policyNode then
              { linkName = null; via4 = null; via6 = null; }
            else
              nextHop { inherit links; from = nodeName; to = policyNode; };

          nhToUpstream =
            if nodeName == upstreamNode then
              { linkName = null; via4 = null; via6 = null; }
            else
              nextHop { inherit links; from = nodeName; to = upstreamNode; };

          nhToCore =
            if nodeName == coreNode then
              { linkName = null; via4 = null; via6 = null; }
            else
              nextHop { inherit links; from = nodeName; to = coreNode; };

        in
        if role == "access" then
          let
            _ = requireHop { from = nodeName; to = policyNode; hop = nhToPolicy; fam = 4; };
            _6 = requireHop { from = nodeName; to = policyNode; hop = nhToPolicy; fam = 6; };
          in
          {
            tenantLink = null;
            routes4Tenant = [ ];
            routes6Tenant = [ ];

            defaultLink = nhToPolicy.linkName;
            routes4Default = [ (mkRoute4 default4 nhToPolicy.via4) ];
            routes6Default = [ (mkRoute6 default6 nhToPolicy.via6) ];
          }

        else if role == "policy" then
          let
            _a4 = requireHop { from = nodeName; to = accessNode; hop = nhToAccess; fam = 4; };
            _a6 = requireHop { from = nodeName; to = accessNode; hop = nhToAccess; fam = 6; };
            _u4 = requireHop { from = nodeName; to = upstreamNode; hop = nhToUpstream; fam = 4; };
            _u6 = requireHop { from = nodeName; to = upstreamNode; hop = nhToUpstream; fam = 6; };
          in
          {
            tenantLink = nhToAccess.linkName;
            routes4Tenant = map (p: mkRoute4 p nhToAccess.via4) t4;
            routes6Tenant = map (p: mkRoute6 p nhToAccess.via6) t6;

            defaultLink = nhToUpstream.linkName;
            routes4Default = [ (mkRoute4 default4 nhToUpstream.via4) ];
            routes6Default = [ (mkRoute6 default6 nhToUpstream.via6) ];
          }

        else if role == "upstream-selector" then
          let
            _p4 = requireHop { from = nodeName; to = policyNode; hop = nhToPolicy; fam = 4; };
            _p6 = requireHop { from = nodeName; to = policyNode; hop = nhToPolicy; fam = 6; };
            _c4 = requireHop { from = nodeName; to = coreNode; hop = nhToCore; fam = 4; };
            _c6 = requireHop { from = nodeName; to = coreNode; hop = nhToCore; fam = 6; };
          in
          {
            tenantLink = nhToPolicy.linkName;
            routes4Tenant = map (p: mkRoute4 p nhToPolicy.via4) t4;
            routes6Tenant = map (p: mkRoute6 p nhToPolicy.via6) t6;

            defaultLink = nhToCore.linkName;
            routes4Default = [ (mkRoute4 default4 nhToCore.via4) ];
            routes6Default = [ (mkRoute6 default6 nhToCore.via6) ];
          }

        else if role == "core" then
          let
            _u4 = requireHop { from = nodeName; to = upstreamNode; hop = nhToUpstream; fam = 4; };
            _u6 = requireHop { from = nodeName; to = upstreamNode; hop = nhToUpstream; fam = 6; };
          in
          {
            tenantLink = nhToUpstream.linkName;
            routes4Tenant = map (p: mkRoute4 p nhToUpstream.via4) t4;
            routes6Tenant = map (p: mkRoute6 p nhToUpstream.via6) t6;

            defaultLink = null;
            routes4Default = [ { dst = default4; } ];
            routes6Default = [ { dst = default6; } ];
          }

        else
          {
            tenantLink = null;
            routes4Tenant = [ ];
            routes6Tenant = [ ];
            defaultLink = null;
            routes4Default = [ ];
            routes6Default = [ ];
          };

      stepNode =
        acc: nodeName:
        let
          node = acc.${nodeName};

          cleared =
            node
            // {
              interfaces =
                lib.mapAttrs (_: iface: iface // { routes4 = [ ]; routes6 = [ ]; }) (node.interfaces or { });
            };

          r = mkNodeRoutes nodeName;

          node1 = setIfaceRoutes cleared r.tenantLink r.routes4Tenant r.routes6Tenant;
          node2 = setIfaceRoutes node1 r.defaultLink r.routes4Default r.routes6Default;
        in
        acc // { "${nodeName}" = node2; };

      nodes1 = builtins.foldl' stepNode nodes0 (builtins.attrNames nodes0);

    in
    topo
    // {
      nodes = nodes1;

      _routingMaps = {
        mode = "static";
        defaults = { inherit default4 default6; };
        tenants = { ipv4 = t4; ipv6 = t6; };

        assumptions = {
          singleAccess = accessNode;
          policy = policyNode;
          upstreamSelector = upstreamNode;
          core = coreNode;
        };
      };
    };
}
