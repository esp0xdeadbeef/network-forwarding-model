{ lib, ... }:

ordering:
let
  edges = map (p: { a = builtins.elemAt p 0; b = builtins.elemAt p 1; }) (
    lib.filter (p: builtins.isList p && builtins.length p == 2) ordering
  );

  nodes = lib.unique (lib.concatMap (e: [ e.a e.b ]) edges);

  countIn = n: xs: builtins.length (lib.filter (x: x == n) xs);
  indeg = n: countIn n (map (e: e.b) edges);
  outdeg = n: countIn n (map (e: e.a) edges);
  outsOf = n: lib.filter (e: e.a == n) edges;
  insOf = n: lib.filter (e: e.b == n) edges;

  allowFanoutHere =
    n:
    let
      outs = outsOf n;
      targets = map (e: e.b) outs;
    in
    (builtins.length outs) > 1 && lib.all (t: outdeg t == 0) targets && (indeg n) > 0;

  nextOf =
    n:
    let outs = outsOf n;
    in
    if outs == [ ] then null
    else if builtins.length outs == 1 then (builtins.elemAt outs 0).b
    else if allowFanoutHere n then null
    else throw "network-forwarding-model: transit.ordering must not branch from '${n}' (multiple outgoing edges)";

  root =
    let roots = lib.filter (n: indeg n == 0) nodes;
    in if roots == [ ] then null else lib.head (lib.sort (a: b: a < b) roots);

  chain =
    let
      go =
        seen: cur:
        if cur == null then seen
        else if lib.elem cur seen then throw "network-forwarding-model: transit.ordering contains a cycle at '${cur}'"
        else go (seen ++ [ cur ]) (nextOf cur);
    in
    if root == null then [ ] else go [ ] root;

in
{
  inherit
    chain
    edges
    indeg
    insOf
    nodes
    outsOf
    root
    ;
}
