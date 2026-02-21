{ lib }:

let
  assert_ = cond: msg: if cond then true else throw msg;

  isV4 = cidr: lib.hasInfix "." (toString cidr);

  splitCidr =
    cidr:
    let
      parts = lib.splitString "/" (toString cidr);
    in
    if builtins.length parts != 2 then
      throw "invariants(global-p2p-pool): invalid CIDR '${toString cidr}'"
    else
      {
        ip = builtins.elemAt parts 0;
        prefix = lib.toInt (builtins.elemAt parts 1);
      };

  parseOctet =
    s:
    let
      n = lib.toInt s;
    in
    if n < 0 || n > 255 then throw "invariants(global-p2p-pool): bad IPv4 octet '${s}'" else n;

  parseV4 =
    s:
    let
      p = lib.splitString "." s;
    in
    if builtins.length p != 4 then
      throw "invariants(global-p2p-pool): bad IPv4 '${s}'"
    else
      map parseOctet p;

  v4ToInt =
    o:
    (((builtins.elemAt o 0) * 256 + (builtins.elemAt o 1)) * 256 + (builtins.elemAt o 2)) * 256
    + (builtins.elemAt o 3);

  pow2 = n: if n <= 0 then 1 else 2 * pow2 (n - 1);

  v4Range =
    cidr:
    let
      c = splitCidr cidr;
      base = v4ToInt (parseV4 c.ip);
      size = pow2 (32 - c.prefix);
    in
    {
      start = base;
      end = base + size - 1;
      cidr = toString cidr;
    };

  overlaps = a: b: !(a.end < b.start || b.end < a.start);

  assertIPv6PoolPrefixOk =
    { siteKey, cidr }:
    let
      c = splitCidr cidr;
      p = c.prefix;
    in
    assert_ (!isV4 cidr) ''
      invariants(global-p2p-pool):

      site '${siteKey}' has p2p-pool.ipv6 that looks like IPv4:

        ${toString cidr}
    ''
    && assert_ (p <= 120) ''
      invariants(global-p2p-pool):

      site '${siteKey}' p2p-pool.ipv6 is too small for p2p addressing:

        ${toString cidr}

      This compiler requires at least a /120-sized pool (i.e. /120 or larger like /119,/118,...).
    ''
    && assert_ (p >= 64 && p <= 128) ''
      invariants(global-p2p-pool):

      site '${siteKey}' p2p-pool.ipv6 has invalid prefix length:

        ${toString cidr}

      Expected prefix length between /64 and /128.
    '';

  enterpriseOf =
    siteKey: site:
    if site ? enterprise && builtins.isString site.enterprise then
      site.enterprise
    else
      let
        parts = lib.splitString "." siteKey;
      in
      if builtins.length parts >= 2 then builtins.elemAt parts 0 else "__default__";

  groupByEnterprise =
    sites:
    builtins.foldl' (
      acc: siteKey:
      let
        site = sites.${siteKey};
        e = enterpriseOf siteKey site;
      in
      acc
      // {
        "${e}" = (acc."${e}" or { }) // {
          "${siteKey}" = site;
        };
      }
    ) { } (builtins.attrNames sites);

in
{

  checkAll =
    { sites }:

    let
      byEnt = groupByEnterprise sites;

      checkEnt =
        entName:
        let
          entSites = byEnt.${entName};
          siteKeys = builtins.attrNames entSites;

          pools4 = lib.map (
            siteKey:
            let
              site = entSites.${siteKey};
            in
            if !(site ? p2p-pool) || !(site.p2p-pool ? ipv4) then
              throw ''
                invariants(global-p2p-pool):

                (enterprise: ${entName})

                site '${siteKey}' is missing required p2p-pool.ipv4
              ''
            else
              {
                site = siteKey;
                cidr = toString site.p2p-pool.ipv4;
                range = v4Range site.p2p-pool.ipv4;
              }
          ) siteKeys;

          pairs4 = lib.concatMap (
            i:
            let
              a = builtins.elemAt pools4 i;
            in
            map (
              j:
              let
                b = builtins.elemAt pools4 j;
              in
              {
                inherit a b;
              }
            ) (lib.range (i + 1) (builtins.length pools4 - 1))
          ) (lib.range 0 (builtins.length pools4 - 2));

          _v4 = lib.all (
            p:
            assert_ (!(overlaps p.a.range p.b.range)) ''
              invariants(global-p2p-pool):

              (enterprise: ${entName})

              overlapping p2p-pool IPv4 ranges detected:

                ${p.a.site}: ${p.a.cidr}
                ${p.b.site}: ${p.b.cidr}

              Each site inside the same enterprise must use a unique p2p pool.
            ''
          ) pairs4;

          pools6 = lib.map (
            siteKey:
            let
              site = entSites.${siteKey};
            in
            if !(site ? p2p-pool) || !(site.p2p-pool ? ipv6) then
              null
            else
              let
                cidr = toString site.p2p-pool.ipv6;
                _ok = assertIPv6PoolPrefixOk { inherit siteKey cidr; };
              in
              builtins.seq _ok {
                site = siteKey;
                cidr = cidr;
              }
          ) siteKeys;

          pools6' = lib.filter (x: x != null) pools6;

          _v6State = builtins.foldl' (
            acc: e:
            let
              k = e.cidr;
            in
            if acc.seen ? "${k}" then
              throw ''
                invariants(global-p2p-pool):

                (enterprise: ${entName})

                duplicate p2p-pool IPv6 prefix detected within enterprise:

                  ${k}

                first seen in:
                  ${acc.seen.${k}}

                duplicated in:
                  ${e.site}
              ''
            else
              {
                seen = acc.seen // {
                  "${k}" = e.site;
                };
              }
          ) { seen = { }; } pools6';

        in
        builtins.seq _v4 (builtins.seq _v6State true);

      _all = lib.forEach (builtins.attrNames byEnt) checkEnt;

    in
    builtins.deepSeq _all true;
}
