{ lib }:

let
  cidr = import ../../cidr-utils.nix { inherit lib; };

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

          pairs = lib.concatMap (
            i:
            let
              a = builtins.elemAt withRanges i;
            in
            map (
              j:
              let
                b = builtins.elemAt withRanges j;
              in
              {
                inherit a b;
              }
            ) (lib.range (i + 1) (builtins.length withRanges - 1))
          ) (lib.range 0 (builtins.length withRanges - 2));

          _ = lib.all (
            p:
            assert_ (!(overlaps p.a.range p.b.range))
              "invariants(node-roles): overlapping access networks on node '${name}': '${p.a.cidr}' (${p.a.owner}) and '${p.b.cidr}' (${p.b.owner})"
          ) pairs;
        in
        true
    );
}
