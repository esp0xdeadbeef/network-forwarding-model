# ./lib/fabric/invariants/user-prefixes-disjoint.nix
{ lib }:

let
  cidr = import ./cidr-utils.nix { inherit lib; };

  assert_ = cond: msg: if cond then true else throw msg;

  overlaps = a: b: a.family == b.family && !(a.end < b.start || b.end < a.start);

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

      ps = pairs entries;

      checked = lib.all (
        p:
        assert_ (!(overlaps p.a.range p.b.range))
          "invariants(user-prefixes): overlapping user prefixes '${p.a.cidr}' (${p.a.owner}) and '${p.b.cidr}' (${p.b.owner})"
      ) ps;
    in
    builtins.deepSeq checked true;
}
