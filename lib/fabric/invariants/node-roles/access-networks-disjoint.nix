{ lib }:

let
  cidr = import ../cidr-utils.nix { inherit lib; };
  common = import ../common.nix { inherit lib; };
  network = import ../../../model/network-utils.nix { inherit lib; };

  overlaps = a: b: a.family == b.family && !(a.end < b.start || b.end < a.start);
  networksOf = network.networksOfRaw { extraExcluded = [ ]; };

in
{
  check =
    { nodes }:

    lib.forEach (builtins.attrNames nodes) (
      name:
      let
        n = nodes.${name};
        nets = networksOf n;
      in
      if (n.role or "") != "access" || nets == { } then
        true
      else
        let
          entries = lib.flatten (
            lib.mapAttrsToList (
              netName: net:
              lib.flatten [
                (lib.optional (net ? ipv4) {
                  cidr = net.ipv4;
                  owner = "node '${name}' network '${netName}' ipv4";
                })
                (lib.optional (net ? ipv6) {
                  cidr = net.ipv6;
                  owner = "node '${name}' network '${netName}' ipv6";
                })
              ]
            ) nets
          );

          withRanges = map (e: e // { range = cidr.cidrRange e.cidr; }) entries;

          ps = common.pairs withRanges;

          _ = lib.all (
            p:
            common.assert_ (!(overlaps p.a.range p.b.range))
              "invariants(node-roles): overlapping access networks on node '${name}': '${p.a.cidr}' (${p.a.owner}) and '${p.b.cidr}' (${p.b.owner})"
          ) ps;
        in
        true
    );
}
