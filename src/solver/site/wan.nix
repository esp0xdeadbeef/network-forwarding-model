{ lib }:

{
  build =
    {
      lib,
      site,
      localPool,

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

      # Use /30 (IPv4) and /126 (IPv6) so the "core" side
      # always gets the first usable address (.1 / ::1),
      # and the peer gets the second usable (.2 / ::2).
      mkWanNetBase =
        idx:
        100 + (4 * idx);

      mkWanAddr4 =
        hostIndex:
        let base = "${stripMask localPool.ipv4}/30";
        in addr.hostCidr hostIndex base;

      mkWanAddr6 =
        hostIndex:
        let base = "${stripMask localPool.ipv6}/126";
        in addr.hostCidr hostIndex base;

      mkWanLL6 =
        hostIndex:
        addr.hostCidr (hostIndex + 1) "fe80::/128";

      mkWanLink =
        idx: u:
        let
          nm = if builtins.isAttrs u && u ? name then toString u.name else toString u;
          peer = mkWanPeerName nm;

          base = mkWanNetBase idx;

          # .0 = network, .1 = core, .2 = peer, .3 = broadcast
          hCore = base + 1;
          hPeer = base + 2;
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
                addr4 = if localPool ? ipv4 then mkWanAddr4 hCore else null;
                addr6 = if localPool ? ipv6 then mkWanAddr6 hCore else null;
                ll6 = mkWanLL6 hCore;
              };
              "${peer}" = {
                addr4 = if localPool ? ipv4 then mkWanAddr4 hPeer else null;
                addr6 = if localPool ? ipv6 then mkWanAddr6 hPeer else null;
                ll6 = mkWanLL6 hPeer;
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
