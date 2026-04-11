{ lib }:

let
  cidr = import ./cidr-utils.nix { inherit lib; };
  common = import ./common.nix { inherit lib; };
  network = import ../../model/network-utils.nix { inherit lib; };

  overlaps = a: b: a.family == b.family && !(a.end < b.start || b.end < a.start);
  networksOf = network.networksOfRaw { extraExcluded = [ ]; };

  userPrefixEntries =
    nodes:
    lib.concatMap (
      name:
      let
        n = nodes.${name};
        nets = networksOf n;
      in
      lib.concatMap (
        netName:
        let
          net = nets.${netName};
        in
        lib.flatten [
          (lib.optional (net ? ipv4 && net.ipv4 != null) {
            family = 4;
            cidr = toString net.ipv4;
            label = "node '${name}' network '${netName}' ipv4";
            range = cidr.cidrRange net.ipv4;
          })
          (lib.optional (net ? ipv6 && net.ipv6 != null) {
            family = 6;
            cidr = toString net.ipv6;
            label = "node '${name}' network '${netName}' ipv6";
            range = cidr.cidrRange net.ipv6;
          })
        ]
      ) (builtins.attrNames nets)
    ) (builtins.attrNames nodes);

  checkPool =
    {
      siteName,
      label,
      poolCidr,
      entries,
    }:
    if poolCidr == null then
      true
    else
      let
        poolRange = cidr.cidrRange poolCidr;
      in
      lib.all (
        entry:
        common.assert_ (!(overlaps poolRange entry.range)) ''
          invariants(p2p-pool):

          p2p pool overlaps user prefix

          site: ${siteName}
          pool: ${label} (${toString poolCidr})
          prefix: ${entry.label} (${entry.cidr})
        ''
      ) entries;

in
{
  check =
    { site, ... }:
    let
      siteName = toString (site.siteName or "<unknown-site>");
      nodes = site.nodes or { };
      p2pPool = site.p2p-pool or { };
      entries = userPrefixEntries nodes;

      entries4 = lib.filter (e: e.family == 4) entries;
      entries6 = lib.filter (e: e.family == 6) entries;

      _4 = checkPool {
        inherit siteName;
        label = "site.p2p-pool.ipv4";
        poolCidr = p2pPool.ipv4 or null;
        entries = entries4;
      };

      _6 = checkPool {
        inherit siteName;
        label = "site.p2p-pool.ipv6";
        poolCidr = p2pPool.ipv6 or null;
        entries = entries6;
      };
    in
    builtins.seq _4 (builtins.seq _6 true);
}
