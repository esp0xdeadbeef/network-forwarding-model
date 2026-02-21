{ lib }:

input:

let
  mkWanLinks =
    coreNodeName: wan:
    if wan == null then
      { }
    else
      lib.mapAttrs (
        ctx: w:
        let
          coreCtx = "${coreNodeName}-${ctx}";

          dhcp = w.dhcp or false;
          acceptRA = w.acceptRA or false;

          wantDefault4 = dhcp || (w ? routes4) || (w ? ip4);
          wantDefault6 = dhcp || acceptRA || (w ? routes6) || (w ? ip6);

          routes4 =
            if w ? routes4 then
              w.routes4
            else if wantDefault4 then
              [ { dst = "0.0.0.0/0"; } ]
            else
              [ ];

          routes6 =
            if w ? routes6 then
              w.routes6
            else if wantDefault6 then
              [ { dst = "::/0"; } ]
            else
              [ ];
        in
        {
          kind = "wan";
          carrier = "wan";
          vlanId = w.vlanId or 6;
          name = "wan-${ctx}";
          members = [ coreNodeName ];
          endpoints."${coreCtx}" = {
            inherit routes4 routes6;
          }
          // lib.optionalAttrs (w ? ip4) { addr4 = w.ip4; }
          // lib.optionalAttrs (w ? ip6) { addr6 = w.ip6; }
          // lib.optionalAttrs (w ? acceptRA) { acceptRA = w.acceptRA; }
          // lib.optionalAttrs (w ? dhcp) { dhcp = w.dhcp; };
        }
      ) wan;

  policyAccessTransitBase = input.policyAccessTransitBase;
  corePolicyTransitVlan = input.corePolicyTransitVlan;
  ulaPrefix = input.ulaPrefix;
  tenantV4Base = input.tenantV4Base;

  policyAccessOffset = input.policyAccessOffset or 0;

  policyNodeName = if input ? policyNodeName then input.policyNodeName else "s-router-policy-only";

  coreNodeName = if input ? coreNodeName then input.coreNodeName else "s-router-core";

  accessNodePrefix = if input ? accessNodePrefix then input.accessNodePrefix else "s-router-access";

  domain = input.domain or "lan.";
  reservedVlans = input.reservedVlans or [ 1 ];
  forbiddenVlanRanges =
    if !(input ? forbiddenVlanRanges) then
      throw ''
        Missing required attribute: forbiddenVlanRanges

        This compiler does NOT invent forbidden VLAN policy defaults.

        Fix: set an explicit policy in your inputs, e.g.

          forbiddenVlanRanges = [ ];

        Or provide ranges:

          forbiddenVlanRanges = [ { from = 2; to = 9; } ];
      ''
    else
      input.forbiddenVlanRanges;
  defaultRouteMode = input.defaultRouteMode or "default";
  extraLinks = input.links or { };
  wan = input.wan or null;
  coreRoutingNodeName = input.coreRoutingNodeName or null;

  topoRaw = import ../topology-gen.nix { inherit lib; } (
    input
    // {
      inherit
        policyAccessTransitBase
        corePolicyTransitVlan
        policyAccessOffset
        policyNodeName
        coreNodeName
        accessNodePrefix
        domain
        reservedVlans
        forbiddenVlanRanges
        ulaPrefix
        tenantV4Base
        ;
    }
  );

  topoWithLinks = topoRaw // {
    inherit defaultRouteMode coreRoutingNodeName;
    links = (topoRaw.links or { }) // extraLinks // (mkWanLinks coreNodeName wan);
  };

  topoResolved = import ../topology-resolve.nix {
    inherit lib ulaPrefix tenantV4Base;
  } topoWithLinks;

in
import ../compile/compile.nix {
  inherit lib;
  model = topoResolved;
}
