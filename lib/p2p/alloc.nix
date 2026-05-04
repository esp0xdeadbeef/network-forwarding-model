{ lib }:

let
  addr = import ../model/addressing.nix { inherit lib; };
  ip = import ../net/ip-utils.nix { inherit lib; };
  linkSpecs = import ./link-specs.nix { inherit lib; };

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
      links = linkSpecs.validate site.links;

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
              }
              // lib.optionalAttrs ((p.overlay or null) != null) { overlay = p.overlay; }
              // lib.optionalAttrs ((p.uplinks or null) != null) { uplinks = p.uplinks; }
              // {
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
