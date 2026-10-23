#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-460-HDS-010-SDS-010-SMS-010
# GAMP-SCOPE: software-module-test
#
# terminatesOverlays is ROLE authority and comes from intent
# (site.transport.overlays[].terminateOn) alone.
#
# `overlayReachability` is the resolved per-overlay EXIT / peer-route record: it
# carries routes toward a peer site and its `terminateOn` is merged across every
# peer via mergeReachability.  A node that merely holds a peer route appears
# there but is NOT the overlay's terminating endpoint.  Consulting that record
# (regression introduced by `fix(FS-460): read overlay terminateOn from
# overlayReachability too`) made a plain client-egress core look like an overlay
# terminator, which moved client-egress forwarding rules onto it and broke
# client WAN egress (routes/traceroutes) while the overlay itself looked fine.
#
# This test fails closed on that regression: a core named only in
# overlayReachability must report terminatesOverlays = false.

repo_root="$(git rev-parse --show-toplevel)"
source "${repo_root}/tests/lib/timing.sh"

start_ms="$(test_now_ms)"
tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

expr_nix="${tmpdir}/fs460-overlay-terminator-from-intent.nix"
result_json="${tmpdir}/fs460-overlay-terminator-from-intent.json"

cat >"${expr_nix}" <<'NIX'
let
  repoRoot = builtins.getEnv "REPO_ROOT";
  flake = builtins.getFlake ("path:" + repoRoot);
  lib = flake.inputs.nixpkgs.lib;
  semanticNode = import (repoRoot + "/implementation/s88/Site/topology/semantic-node.nix") {
    inherit lib;
    self = { outPath = repoRoot; };
  };

  mkSite =
    {
      overlays ? [ ],
      overlayReachability ? { },
    }:
    {
      domains.tenants = [
        {
          name = "client";
          ipv6 = "fd00:460:10::/64";
        }
      ];
      ownership.endpoints = [ ];
      communicationContract = {
        services = [ ];
        relations = [ ];
      };
      providerProfiles.none = { };
      providerProfile = "none";
      services = {
        resolver = { };
        publicIngress = { };
        payload = { };
        management = { };
      };
      routeAvailability = { };
      attachments = [ ];
      transport.overlays = overlays;
      inherit overlayReachability;
    };

  node = {
    kind = "core";
    attachments = [ ];
    addresses = [ ];
    uplinks.wan = { };
  };

  build =
    nodeName: site:
    semanticNode.build {
      inherit nodeName site;
      node = node;
      role = "core";
      siteUplinkCoreNames = [ nodeName ];
      siteUplinkNames = [ "wan" ];
      siteExternalDomains = [ "wan" ];
    };

  # A core that the resolved exit record mentions, but which intent never
  # names as an overlay terminateOn target.  This is the client-egress core.
  nonTerminatingSite = mkSite {
    overlays = [
      {
        name = "garnet";
        terminateOn = "core-vpn-garnet";
        underlayAccess = null;
      }
    ];
    overlayReachability = {
      garnet = {
        overlay = "garnet";
        peerSite = "esp0xdeadbeef.neon";
        peerSites = [ "esp0xdeadbeef.neon" ];
        # Merged across peers: contains the terminating node AND `core`, which
        # only holds the peer route.
        terminateOn = [
          "core-vpn-garnet"
          "core"
        ];
        underlayAccess = null;
        routes4 = [ ];
        routes6 = [ ];
      };
    };
  };

  # Control: the node intent actually names IS a terminator.
  terminatingSite = mkSite {
    overlays = [
      {
        name = "garnet";
        terminateOn = "core";
        underlayAccess = null;
      }
    ];
  };

  egressCore = build "core" nonTerminatingSite;
  vpnCore = build "core-vpn-garnet" nonTerminatingSite;
  realTerminator = build "core" terminatingSite;
in
{
  # The client-egress core must NOT become an overlay terminator just because
  # the resolved peer-route record mentions it.
  egressCoreTerminates = egressCore.forwardingResponsibility.terminatesOverlays;
  vpnCoreTerminates = vpnCore.forwardingResponsibility.terminatesOverlays;
  # Intent authority still works.
  intentTerminatorTerminates = realTerminator.forwardingResponsibility.terminatesOverlays;
}
NIX

REPO_ROOT="${repo_root}" nix eval --impure --json --file "${expr_nix}" >"${result_json}"

jq -e '
  (.egressCoreTerminates == false)
  and (.vpnCoreTerminates == true)
  and (.intentTerminatorTerminates == true)
' "${result_json}" >/dev/null

elapsed_ms=$(( $(test_now_ms) - start_ms ))
printf 'ok: fs-460 overlay terminator derives from intent (%sms)\n' "${elapsed_ms}"
