{ lib, self ? { outPath = ./.; }, ... }:

let
  cidr = import ./cidr-utils.nix { inherit lib self; };
  common = import ./common.nix { inherit lib self; };
  enterprise = import ./enterprise-utils.nix { inherit lib self; };
  network = import (self.outPath + "/implementation/lib/model/network-utils.nix") { inherit lib self; };

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

          entries = lib.concatMap
            (
              siteKey:
              let
                site = entSites.${siteKey};
                nodes = site.nodes or { };
              in
              lib.concatMap
                (
                  nodeName:
                  let
                    n = nodes.${nodeName};
                    nets = networksOf n;
                  in
                  lib.concatMap
                    (
                      netName:
                      let
                        net = nets.${netName};
                        ownsPrefix = (net.gateway or true) != false;
                      in
                      lib.flatten [
                        (lib.optional (ownsPrefix && net ? ipv4 && net.ipv4 != null) {
                          cidr = toString net.ipv4;
                          owner = "${siteKey}: node '${nodeName}' network '${netName}' ipv4";
                          range = cidr.cidrRange net.ipv4;
                        })
                        (lib.optional (ownsPrefix && net ? ipv6 && net.ipv6 != null) {
                          cidr = toString net.ipv6;
                          owner = "${siteKey}: node '${nodeName}' network '${netName}' ipv6";
                          range = cidr.cidrRange net.ipv6;
                        })
                      ]
                    )
                    (builtins.attrNames nets)
                )
                (builtins.attrNames nodes)
            )
            siteNames;

          ps = common.pairs entries;

          _ = lib.all
            (
              p:
              let
                aNet = builtins.match ".*network '([^']+)'.*" p.a.owner;
                bNet = builtins.match ".*network '([^']+)'.*" p.b.owner;
                sameNet = aNet != null && bNet != null && (builtins.head aNet) == (builtins.head bNet);
              in
              if sameNet then true
              else common.assert_ (!(overlaps p.a.range p.b.range)) ''
                invariants(global-user-space):

                (enterprise: ${entName})

                overlapping user prefixes detected:

                  ${p.a.cidr}  (${p.a.owner})
                  ${p.b.cidr}  (${p.b.owner})
              ''
            )
            ps;
        in
        true;

      _all = lib.forEach (builtins.attrNames byEnt) checkOneEnterprise;
    in
    builtins.deepSeq _all true;
}
