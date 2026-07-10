{ lib, self ? { outPath = ./.; }, ... }:

let
  cidr = import ./cidr-utils.nix { inherit lib self; };
  common = import ./common.nix { inherit lib self; };
  network = import (self.outPath + "/implementation/lib/model/network-utils.nix") { inherit lib self; };

  overlaps = a: b: a.family == b.family && !(a.end < b.start || b.end < a.start);
  networksOf = network.networksOfRaw { extraExcluded = [ ]; };

in
{
  check =
    { nodes }:
    let
      entries = lib.concatMap
        (
          name:
          let
            n = nodes.${name};
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
                  cidr = net.ipv4;
                  owner = "node '${name}' network '${netName}' ipv4";
                  range = cidr.cidrRange net.ipv4;
                })
                (lib.optional (ownsPrefix && net ? ipv6 && net.ipv6 != null) {
                  cidr = net.ipv6;
                  owner = "node '${name}' network '${netName}' ipv6";
                  range = cidr.cidrRange net.ipv6;
                })
              ]
            )
            (builtins.attrNames nets)
        )
        (builtins.attrNames nodes);

      ps = common.pairs entries;

      checked = lib.all
        (
          p:
          let
            # Shared-tenant fabric: same network name on different nodes
            # uses the same prefix; don't flag as overlapping.
            aNet = builtins.match ".*network '([^']+)'.*" p.a.owner;
            bNet = builtins.match ".*network '([^']+)'.*" p.b.owner;
            sameNet = aNet != null && bNet != null && (builtins.head aNet) == (builtins.head bNet);
          in
          if sameNet then true
          else common.assert_ (!(overlaps p.a.range p.b.range))
            "invariants(user-prefixes): overlapping user prefixes '${p.a.cidr}' (${p.a.owner}) and '${p.b.cidr}' (${p.b.owner})"
        )
        ps;
    in
    builtins.deepSeq checked true;
}
