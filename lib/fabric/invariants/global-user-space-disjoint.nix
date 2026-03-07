{ lib }:

let
  cidr = import ./cidr-utils.nix { inherit lib; };
  common = import ./common.nix { inherit lib; };
  enterprise = import ./enterprise-utils.nix { inherit lib; };
  network = import ../../model/network-utils.nix { inherit lib; };

  overlaps = a: b: a.family == b.family && !(a.end < b.start || b.end < a.start);
  networksOf = network.networksOfRaw { extraExcluded = [ ]; };

in
{
  checkAll =
    { sites }:

    let
      byEnt = enterprise.groupByEnterprise sites;

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

          ps = common.pairs entries;

          _ = lib.all (
            p:
            common.assert_ (!(overlaps p.a.range p.b.range)) ''
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
