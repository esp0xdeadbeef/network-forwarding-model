{ lib }:

let
  addr = import ../model/addressing.nix { inherit lib; };
  ip = import ../net/ip-utils.nix { inherit lib; };

  v4ToInt = ip.ipv4ToInt;
  parseV4 = ip.parseIPv4;
  intToV4 = ip.intToIPv4;

  pow2 = n: builtins.foldl' (acc: _: acc * 2) 1 (lib.range 1 n);

  rangeV4 =
    cidr:
    let
      c = ip.splitCidr cidr;
      base = v4ToInt (parseV4 c.ip);
      size = pow2 (32 - c.prefix);
    in
    {
      start = base;
      end = base + size - 1;
    };

  overlaps = a: b: !(a.end < b.start || b.end < a.start);

  normPair =
    a0: b0:
    let
      a = toString a0;
      b = toString b0;
    in
    if a < b then
      { inherit a b; }
    else
      {
        a = b;
        b = a;
      };

  sanitize =
    s:
    let
      raw = toString s;
      chars = lib.stringToCharacters raw;
      ok =
        c:
        (c >= "a" && c <= "z") || (c >= "A" && c <= "Z") || (c >= "0" && c <= "9") || c == "-" || c == "_";
      normalized = builtins.concatStringsSep "" (map (c: if ok c then c else "-") chars);
    in
    if normalized == "" then "lane" else normalized;

  linkNameFor =
    p:
    let
      lane = p.lane or "default";
      laneHash = builtins.substring 0 10 (builtins.hashString "sha256" (toString lane));
      laneSlug = sanitize lane;
    in
    if lane == "default" then
      "p2p-${p.a}-${p.b}"
    else
      "p2p-${p.a}-${p.b}--lane-${laneSlug}-${laneHash}";

  normalizeLinkSpec =
    link:
    if builtins.isList link && builtins.length link == 2 then
      let
        p = normPair (builtins.elemAt link 0) (builtins.elemAt link 1);
      in
      p
      // {
        lane = "default";
        linkName = linkNameFor (p // { lane = "default"; });
      }
    else if builtins.isAttrs link then
      let
        a0 = link.a or null;
        b0 = link.b or null;
        _ =
          if a0 == null || b0 == null then
            throw "network-forwarding-model: p2p link spec requires a and b"
          else
            true;
        p = normPair a0 b0;
        lane = if (link.lane or null) == null then "default" else toString link.lane;
        p' = p // {
          inherit lane;
        };
        explicitName = link.name or link.linkName or null;
        linkName =
          if explicitName != null && toString explicitName != "" then
            toString explicitName
          else
            linkNameFor p';
      in
      p' // { inherit linkName; }
    else
      throw "network-forwarding-model: invalid p2p link spec (expected [a b] or { a, b, lane? })";

  validateLinkSpecs =
    links:
    let
      specs = map normalizeLinkSpec links;

      step =
        acc: p:
        if p.a == p.b then
          throw ''
            network-forwarding-model: invalid self-link in p2p link specs

            node: ${p.a}
          ''
        else if acc.seen ? "${p.linkName}" then
          throw ''
            network-forwarding-model: duplicate p2p linkName in p2p link specs

            linkName: ${p.linkName}
          ''
        else
          {
            seen = acc.seen // {
              "${p.linkName}" = true;
            };
            specs = acc.specs ++ [ p ];
          };

      res = builtins.foldl' step {
        seen = { };
        specs = [ ];
      } specs;
    in
    lib.sort (x: y: x.linkName < y.linkName) res.specs;

  allocIPv6Pair =
    { pool, linkIndex }:
    let
      c = ip.splitCidr pool;
      hostBase = linkIndex * 2;

      a = addr.hostCidr hostBase "${c.ip}/127";
      b = addr.hostCidr (hostBase + 1) "${c.ip}/127";
    in
    {
      inherit a b;
    };

in
{
  alloc =
    { site }:
    let
      p2p = site.p2p-pool;
      links = validateLinkSpecs site.links;

      v4 = ip.splitCidr p2p.ipv4;
      base4 = v4ToInt (parseV4 v4.ip);

      pool6 = p2p.ipv6 or null;

      userRanges =
        let
          nodes = site.nodes or { };
          domains = site.domains or { };
          tenants = domains.tenants or [ ];

          fromNodes = lib.concatMap (
            name:
            let
              n = nodes.${name};
              nets = n.networks or null;
            in
            if nets == null || !(nets ? ipv4) then [ ] else [ (rangeV4 nets.ipv4) ]
          ) (builtins.attrNames nodes);

          fromTenants = lib.concatMap (
            t: if !(builtins.isAttrs t) || !(t ? ipv4) then [ ] else [ (rangeV4 t.ipv4) ]
          ) tenants;
        in
        fromNodes ++ fromTenants;

      ps = links;

      totalHosts = pow2 (32 - v4.prefix);
      maxBlocks = builtins.div totalHosts 2;

      allocOne =
        used: idx:
        if idx >= maxBlocks then
          throw "network-forwarding-model: p2p pool exhausted"
        else
          let
            offA = 2 * idx;
            offB = offA + 1;

            r = {
              start = base4 + offA;
              end = base4 + offB;
            };

            collides = lib.any (u: overlaps u r) (used ++ userRanges);
          in
          if collides then
            allocOne used (idx + 1)
          else
            {
              range = r;
              nextIdx = idx + 1;
            };

      step =
        acc: p:
        let
          found = allocOne acc.used acc.idx;

          hostA = found.range.start;
          hostB = found.range.start + 1;

          addr4A = "${intToV4 hostA}/31";
          addr4B = "${intToV4 hostB}/31";

          linkIndex =
            let
              off = found.range.start - base4;
            in
            builtins.div off 2;

          v6pair =
            if pool6 == null then
              {
                a = null;
                b = null;
              }
            else
              allocIPv6Pair {
                pool = pool6;
                inherit linkIndex;
              };

          linkName = p.linkName;
        in
        {
          idx = found.nextIdx;
          used = acc.used ++ [ found.range ];
          attrs = acc.attrs ++ [
            {
              name = linkName;
              value = {
                kind = "p2p";
                lane = p.lane;
                endpoints = {
                  "${p.a}" = {
                    addr4 = addr4A;
                  }
                  // lib.optionalAttrs (v6pair.a != null) { addr6 = v6pair.a; };

                  "${p.b}" = {
                    addr4 = addr4B;
                  }
                  // lib.optionalAttrs (v6pair.b != null) { addr6 = v6pair.b; };
                };
              };
            }
          ];
        };

      res = builtins.foldl' step {
        idx = 0;
        used = [ ];
        attrs = [ ];
      } ps;

    in
    lib.listToAttrs res.attrs;
}
