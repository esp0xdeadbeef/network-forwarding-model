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

      pref = "${nodeName}-";
      prefKeys = lib.filter (k: lib.hasPrefix pref k) keys;
      byPrefix = if prefKeys == [ ] then null else lib.head (lib.sort (a: b: a < b) prefKeys);
    in
    if exact != null then exact
    else if byLink != null then byLink
    else byPrefix;

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

  roleNames =
    topo: role:
    builtins.attrNames (lib.filterAttrs (_: n: (n.role or null) == role) (topo.nodes or { }));

  firstOrNull = xs: if xs == [ ] then null else lib.head (lib.sort (a: b: a < b) xs);

  roleOrNull = topo: role: firstOrNull (roleNames topo role);

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
          roleOrNull topo "policy";

      upstreamNode =
        if topo ? upstreamSelectorNodeName && topo.upstreamSelectorNodeName != null then
          topo.upstreamSelectorNodeName
        else
          roleOrNull topo "upstream-selector";

      coreNode =
        if topo ? coreNodeName && topo.coreNodeName != null then
          topo.coreNodeName
        else
          roleOrNull topo "core";

      accessNode = roleOrNull topo "access";

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
            if accessNode == null || nodeName == accessNode then
              { linkName = null; via4 = null; via6 = null; }
            else
              nextHop { inherit links; from = nodeName; to = accessNode; };

          nhToPolicy =
            if policyNode == null || nodeName == policyNode then
              { linkName = null; via4 = null; via6 = null; }
            else
              nextHop { inherit links; from = nodeName; to = policyNode; };

          nhToUpstream =
            if upstreamNode == null || nodeName == upstreamNode then
              { linkName = null; via4 = null; via6 = null; }
            else
              nextHop { inherit links; from = nodeName; to = upstreamNode; };

          nhToCore =
            if coreNode == null || nodeName == coreNode then
              { linkName = null; via4 = null; via6 = null; }
            else
              nextHop { inherit links; from = nodeName; to = coreNode; };

        in
        if role == "access" then
          {
            tenantLink = null;
            routes4Tenant = [ ];
            routes6Tenant = [ ];

            defaultLink = nhToPolicy.linkName;
            routes4Default =
              if nhToPolicy.via4 == null then [ ] else [ (mkRoute4 default4 nhToPolicy.via4) ];
            routes6Default =
              if nhToPolicy.via6 == null then [ ] else [ (mkRoute6 default6 nhToPolicy.via6) ];
          }

        else if role == "policy" then
          {
            tenantLink = nhToAccess.linkName;
            routes4Tenant =
              if nhToAccess.via4 == null then [ ] else map (p: mkRoute4 p nhToAccess.via4) t4;
            routes6Tenant =
              if nhToAccess.via6 == null then [ ] else map (p: mkRoute6 p nhToAccess.via6) t6;

            defaultLink = nhToUpstream.linkName;
            routes4Default =
              if nhToUpstream.via4 == null then [ ] else [ (mkRoute4 default4 nhToUpstream.via4) ];
            routes6Default =
              if nhToUpstream.via6 == null then [ ] else [ (mkRoute6 default6 nhToUpstream.via6) ];
          }

        else if role == "upstream-selector" then
          {
            tenantLink = nhToPolicy.linkName;
            routes4Tenant =
              if nhToPolicy.via4 == null then [ ] else map (p: mkRoute4 p nhToPolicy.via4) t4;
            routes6Tenant =
              if nhToPolicy.via6 == null then [ ] else map (p: mkRoute6 p nhToPolicy.via6) t6;

            defaultLink = nhToCore.linkName;
            routes4Default =
              if nhToCore.via4 == null then [ ] else [ (mkRoute4 default4 nhToCore.via4) ];
            routes6Default =
              if nhToCore.via6 == null then [ ] else [ (mkRoute6 default6 nhToCore.via6) ];
          }

        else if role == "core" then
          {
            tenantLink = nhToUpstream.linkName;
            routes4Tenant =
              if nhToUpstream.via4 == null then [ ] else map (p: mkRoute4 p nhToUpstream.via4) t4;
            routes6Tenant =
              if nhToUpstream.via6 == null then [ ] else map (p: mkRoute6 p nhToUpstream.via6) t6;

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
