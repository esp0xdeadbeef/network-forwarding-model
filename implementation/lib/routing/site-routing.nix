{ lib, ... }:

# Site-level routing style, computed from the intent's required routing
# behaviors (FS-481).
#
# FS-481 makes the routing style a per-scope, intent-owned requirement: a scope
# requires a behavior on its modeled selection, the compiler validates it and
# normalizes the requirement into the node's `behaviors` list, and this module
# emits the site's mode from that normalized output. The mechanism parameters
# (BGP ASN, route-reflector topology, liveness timing, equal-cost weights) are
# inventory or runtime facts and are deliberately not part of this block: the
# forwarding model never reads inventory.
#
# A site whose scopes require no BGP behavior runs the base static scheme.
let
  attrsOrEmpty = a: if builtins.isAttrs a then a else { };

  requiresBgp =
    node:
    builtins.elem "bgp" (
      if builtins.isList (node.behaviors or null) then node.behaviors else [ ]
    );

  siteRouting =
    nodes:
    let
      names = builtins.attrNames (attrsOrEmpty nodes);
      mode =
        if builtins.any (name: requiresBgp (attrsOrEmpty nodes.${name})) names then "bgp" else "static";
    in
    { inherit mode; };
in
{
  inherit siteRouting;
}
