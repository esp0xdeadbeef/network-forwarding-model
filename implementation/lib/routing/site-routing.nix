{ lib, ... }:

# Site-level routing style, computed from the intent's per-boundary uplink
# egress declarations. This is forwarding-model authority: the CPM consumes
# the emitted `routing` block instead of re-deriving the routing style from
# raw intent topology.
#
# FS-481: routing style (static vs bgp) is selected per modeled boundary in
# the intent topology, never from a site-wide inventory mode. When any uplink
# selects bgp, the site runs iBGP with the ASN and topology declared on that
# uplink's egress.bgp (an intent-owned design choice).
let
  attrsOrEmpty = a: if builtins.isAttrs a then a else { };

  uplinkEgresses =
    nodes:
    builtins.concatMap (
      nodeName:
      let
        node = attrsOrEmpty (nodes.${nodeName} or null);
        uplinks = attrsOrEmpty (node.uplinks or null);
      in
      builtins.concatMap (
        uplinkName:
        let
          uplink = attrsOrEmpty (uplinks.${uplinkName} or null);
          egress = attrsOrEmpty (uplink.egress or null);
        in
        [
          {
            inherit nodeName uplinkName;
            mode = egress.mode or "static";
            bgp = attrsOrEmpty (egress.bgp or null);
          }
        ]
      ) (builtins.attrNames uplinks)
    ) (builtins.attrNames (attrsOrEmpty nodes));

  siteRouting =
    nodes:
    let
      egresses = uplinkEgresses nodes;
      mode = if builtins.any (e: e.mode == "bgp") egresses then "bgp" else "static";
      bgp =
        if mode != "bgp" then
          { }
        else
          let
            configured = builtins.filter (e: (attrsOrEmpty e.bgp) != { }) egresses;
            headBgp =
              if configured == [ ] then
                throw "network-forwarding-model: intent topology uplink egress.mode = \"bgp\" requires egress.bgp = { asn = <int>; topology = <str>; }"
              else
                (builtins.head configured).bgp;
          in
          if !builtins.isInt (headBgp.asn or null) then
            throw "network-forwarding-model: intent topology uplink egress.bgp.asn must be an integer"
          else
            {
              asn = headBgp.asn;
              topology = headBgp.topology or "policy-rr";
            };
    in
    { inherit mode; } // (if bgp != { } then { inherit bgp; } else { });
in
{
  inherit siteRouting;
}
