# ./lib/fabric/invariants/global-user-space-disjoint.nix
{ lib }:

let
  cidr = import ./cidr-utils.nix { inherit lib; };

  assert_ = cond: msg: if cond then true else throw msg;

  overlaps = a: b: a.family == b.family && !(a.end < b.start || b.end < a.start);

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

      checkOneEnterprise =
        entName:
        let
          entSites = byEnt.${entName};
          siteNames = builtins.attrNames entSites;

          entries =
            lib.concatMap (
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
                      range = cidr.cidrRange net.ipv4;
                    })
                    (lib.optional (net ? ipv6) {
                      cidr = toString net.ipv6;
                      owner = "${siteKey}: node '${nodeName}' network '${netName}' ipv6";
                      range = cidr.cidrRange net.ipv6;
                    })
                  ]
                ) (builtins.attrNames nets)
              ) (builtins.attrNames nodes)
            ) siteNames;

          ps = pairs entries;

          _ = lib.all (
            p:
            assert_ (!(overlaps p.a.range p.b.range)) ''
              invariants(global-user-space):

              (enterprise: ${entName})

              overlapping user prefixes detected:

                ${p.a.cidr}  (${p.a.owner})
                ${p.b.cidr}  (${p.b.owner})
            ''
          ) ps;
        in
        true;

      _all = lib.forEach (builtins.attrNames byEnt) checkOneEnterprise;
    in
    builtins.deepSeq _all true;
}
