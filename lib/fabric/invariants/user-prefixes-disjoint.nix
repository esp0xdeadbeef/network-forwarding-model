{ lib }:

let
  cidr = import ./cidr-utils.nix { inherit lib; };
  common = import ./common.nix { inherit lib; };

  overlaps = a: b: a.family == b.family && !(a.end < b.start || b.end < a.start);

in
{
  check =
    { nodes }:
    let
      entries = lib.concatMap (
        name:
        let
          n = nodes.${name};
          nets = n.networks or null;
        in
        if nets == null then
          [ ]
        else
          lib.flatten [
            (lib.optional (nets ? ipv4) {
              cidr = nets.ipv4;
              owner = "node '${name}' ipv4";
              range = cidr.cidrRange nets.ipv4;
            })
            (lib.optional (nets ? ipv6) {
              cidr = nets.ipv6;
              owner = "node '${name}' ipv6";
              range = cidr.cidrRange nets.ipv6;
            })
          ]
      ) (builtins.attrNames nodes);

      ps = common.pairs entries;

      checked = lib.all (
        p:
        common.assert_ (!(overlaps p.a.range p.b.range))
          "invariants(user-prefixes): overlapping user prefixes '${p.a.cidr}' (${p.a.owner}) and '${p.b.cidr}' (${p.b.owner})"
      ) ps;
    in
    builtins.deepSeq checked true;
}
