# ./lib/fabric/invariants/global-p2p-pool-disjoint.nix
{ lib }:

let
  cidr = import ./cidr-utils.nix { inherit lib; };

  assert_ = cond: msg: if cond then true else throw msg;

  overlaps = a: b: a.family == b.family && !(a.end < b.start || b.end < a.start);

  assertIPv6PoolPrefixOk =
    { siteKey, cidrStr }:
    let
      parts = lib.splitString "/" (toString cidrStr);
      p = if builtins.length parts == 2 then lib.toInt (builtins.elemAt parts 1) else -1;
      isV4 = lib.hasInfix "." (toString cidrStr);
    in
    assert_ (!isV4) ''
      invariants(global-p2p-pool):

      site '${siteKey}' has p2p-pool.ipv6 that looks like IPv4:

        ${toString cidrStr}
    ''
    && assert_ (p <= 120) ''
      invariants(global-p2p-pool):

      site '${siteKey}' p2p-pool.ipv6 is too small for p2p addressing:

        ${toString cidrStr}

      This compiler requires at least a /120-sized pool (i.e. /120 or larger like /119,/118,...).
    ''
    && assert_ (p >= 64 && p <= 128) ''
      invariants(global-p2p-pool):

      site '${siteKey}' p2p-pool.ipv6 has invalid prefix length:

        ${toString cidrStr}

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

  pairs =
    xs:
    lib.concatMap (
      i:
      let
        a = builtins.elemAt xs i;
      in
      map (
        j:
        let
          b = builtins.elemAt xs j;
        in
        { inherit a b; }
      ) (lib.range (i + 1) (builtins.length xs - 1))
    ) (lib.range 0 (builtins.length xs - 2));

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

          pools =
            lib.concatMap (
              siteKey:
              let
                site = entSites.${siteKey};
                pool = site.p2p-pool or null;
              in
              if pool == null then
                throw ''
                  invariants(global-p2p-pool):

                  (enterprise: ${entName})

                  site '${siteKey}' is missing required p2p-pool
                ''
              else
                lib.flatten [
                  (lib.optional (pool ? ipv4) {
                    site = siteKey;
                    family = 4;
                    cidr = toString pool.ipv4;
                    range = cidr.cidrRange pool.ipv4;
                  })
                  (lib.optional (pool ? ipv6) (
                    let
                      cidr6 = toString pool.ipv6;
                      _ok = assertIPv6PoolPrefixOk { inherit siteKey; cidrStr = cidr6; };
                    in
                    builtins.seq _ok {
                      site = siteKey;
                      family = 6;
                      cidr = cidr6;
                      range = cidr.cidrRange cidr6;
                    }
                  ))
                ]
            ) siteKeys;

          ps = pairs pools;

          _ = lib.all (
            p:
            assert_ (!(overlaps p.a.range p.b.range)) ''
              invariants(global-p2p-pool):

              (enterprise: ${entName})

              overlapping p2p-pool ranges detected:

                ${p.a.site}: ${p.a.cidr}
                ${p.b.site}: ${p.b.cidr}

              Each site inside the same enterprise must use a unique, non-overlapping p2p pool.
            ''
          ) ps;
        in
        true;

      _all = lib.forEach (builtins.attrNames byEnt) checkEnt;
    in
    builtins.deepSeq _all true;
}
