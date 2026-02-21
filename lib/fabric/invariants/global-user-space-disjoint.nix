{ lib }:

let
  assert_ = cond: msg: if cond then true else throw msg;

  isV4 = cidr: lib.hasInfix "." cidr;

  splitCidr =
    cidr:
    let
      parts = lib.splitString "/" cidr;
    in
    if builtins.length parts != 2 then
      throw "invariants(global-user-space): invalid CIDR '${cidr}'"
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
    if n < 0 || n > 255 then throw "invariants(global-user-space): bad IPv4 octet '${s}'" else n;

  parseV4 =
    s:
    let
      p = lib.splitString "." s;
    in
    if builtins.length p != 4 then
      throw "invariants(global-user-space): bad IPv4 '${s}'"
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
      cidr = cidr;
      prefix = c.prefix;
    };

  overlaps = a: b: !(a.end < b.start || b.end < a.start);

  isNetworkAttr =
    name: v:
    builtins.isAttrs v
    && (v ? ipv4 || v ? ipv6)
    && !(lib.elem name [
      "role"
      "interfaces"
      "networks"
    ]);

  networksOf = node: if node ? networks then node.networks else lib.filterAttrs isNetworkAttr node;

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

      checkOneEnterprise =
        entName:
        let
          entSites = byEnt.${entName};
          siteNames = builtins.attrNames entSites;

          entries = lib.concatMap (
            siteKey:
            let
              site = entSites.${siteKey};
              nodes = site.nodes or { };
            in
            lib.concatMap (
              nodeName:
              let
                n = nodes.${nodeName};
                nets = networksOf n;
              in
              lib.concatMap (
                netName:
                let
                  net = nets.${netName};
                in
                lib.flatten [
                  (lib.optional (net ? ipv4) {
                    cidr = toString net.ipv4;
                    owner = "${siteKey}: node '${nodeName}' network '${netName}' ipv4";
                  })
                  (lib.optional (net ? ipv6) {
                    cidr = toString net.ipv6;
                    owner = "${siteKey}: node '${nodeName}' network '${netName}' ipv6";
                  })
                ]
              ) (builtins.attrNames nets)
            ) (builtins.attrNames nodes)
          ) siteNames;

          v4Entries = lib.filter (e: isV4 e.cidr) entries;
          v6Entries = lib.filter (e: !(isV4 e.cidr)) entries;

          v4WithRanges = map (e: e // { range = v4Range e.cidr; }) v4Entries;

          v4Pairs = lib.concatMap (
            i:
            let
              a = builtins.elemAt v4WithRanges i;
            in
            map (
              j:
              let
                b = builtins.elemAt v4WithRanges j;
              in
              {
                inherit a b;
              }
            ) (lib.range (i + 1) (builtins.length v4WithRanges - 1))
          ) (lib.range 0 (builtins.length v4WithRanges - 2));

          _v4Check = lib.all (
            p:
            assert_ (!(overlaps p.a.range p.b.range)) ''
              invariants(global-user-space):

              (enterprise: ${entName})

              overlapping IPv4 prefixes detected:

                ${p.a.cidr}  (${p.a.owner})
                ${p.b.cidr}  (${p.b.owner})
            ''
          ) v4Pairs;

          _v6State = builtins.foldl' (
            acc: e:
            let
              k = e.cidr;
            in
            if acc.seen ? "${k}" then
              throw ''
                invariants(global-user-space):

                (enterprise: ${entName})

                duplicate IPv6 prefix detected within enterprise:

                  ${k}

                first seen in:
                  ${acc.seen.${k}}

                duplicated in:
                  ${e.owner}
              ''
            else
              {
                seen = acc.seen // {
                  "${k}" = e.owner;
                };
              }
          ) { seen = { }; } v6Entries;

        in
        builtins.seq _v4Check (builtins.seq _v6State true);

      _all = lib.forEach (builtins.attrNames byEnt) checkOneEnterprise;

    in
    builtins.deepSeq _all true;
}
