{ lib }:

{
  build =
    {
      lib,
      site,
      localPool,

      # Back-compat: caller may pass either rolesResult or roleFromInput/nodesBase explicitly
      rolesResult ? null,
      roleFromInput ? (if rolesResult != null then rolesResult.roleFromInput else (_: null)),
      nodesBase ? (site.units or site.nodes or { }),
    }:

    let
      addr = import ../../../lib/model/addressing.nix { inherit lib; };

      stripMask =
        cidr:
        let parts = lib.splitString "/" (toString cidr);
        in if builtins.length parts == 0 then toString cidr else builtins.elemAt parts 0;

      allUnits = builtins.attrNames nodesBase;

      coreUnits = lib.filter (u: (roleFromInput u) == "core") allUnits;

      coreUnit =
        if coreUnits == [ ] then
          throw "network-solver: expected at least one unit with role='core'"
        else
          builtins.elemAt (lib.sort (a: b: toString a < toString b) coreUnits) 0;

      upstreamList =
        if site ? upstreams && site.upstreams ? cores
           && site.upstreams.cores ? "${coreUnit}"
        then site.upstreams.cores.${coreUnit}
        else [ ];

      mkWanPeerName = nm: "wan-peer-${coreUnit}-${nm}";

      mkWanPeerNode =
        nm:
        {
          name = mkWanPeerName nm;
          value = {
            role = "core";
            isolated = true;
            containers = [ "default" ];
            routingDomain = "vrf-default";
          };
        };

      wanPeerNodes =
        lib.listToAttrs (map
          (u:
            let nm = if builtins.isAttrs u && u ? name then toString u.name else toString u;
            in mkWanPeerNode nm)
          upstreamList);

      # P2P WAN addressing: /31 (v4) and /127 (v6) on BOTH endpoints.
      mkWanAddr4 =
        host:
        let base = "${stripMask localPool.ipv4}/31";
        in addr.hostCidr host base;

      mkWanAddr6 =
        host:
        let base = "${stripMask localPool.ipv6}/127";
        in addr.hostCidr host base;

      mkWanLL6 =
        idx: addr.hostCidr (idx + 1) "fe80::/128";

      mkWanLink =
        idx: u:
        let
          nm = if builtins.isAttrs u && u ? name then toString u.name else toString u;
          peer = mkWanPeerName nm;

          # Allocate 2 hosts per WAN link (even/odd) so each link is a unique /31 + /127.
          h0 = 100 + (2 * idx);
          h1 = h0 + 1;
        in
        {
          name = "wan-${coreUnit}-${nm}";
          value = {
            kind = "wan";
            carrier = "wan";
            upstream = nm;
            overlay = null;
            members = [ coreUnit peer ];
            endpoints = {
              "${coreUnit}" = {
                gateway = true;
                export = true;
                addr4 = if localPool ? ipv4 then mkWanAddr4 h0 else null;
                addr6 = if localPool ? ipv6 then mkWanAddr6 h0 else null;
                ll6 = mkWanLL6 idx;
              };
              "${peer}" = {
                addr4 = if localPool ? ipv4 then mkWanAddr4 h1 else null;
                addr6 = if localPool ? ipv6 then mkWanAddr6 h1 else null;
                ll6 = mkWanLL6 (idx + 1000);
              };
            };
          };
        };

      wanLinks = lib.listToAttrs (lib.imap0 mkWanLink upstreamList);

    in
    {
      inherit coreUnit wanPeerNodes wanLinks;
    };
}
