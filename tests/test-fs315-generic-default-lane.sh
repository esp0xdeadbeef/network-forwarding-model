#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-315-HDS-010-SDS-010-SMS-010
# GAMP-SCOPE: software-module-test
#
# A generic default may only be installed on a lane whose modeled uplink offers a
# default in that address family.
#
# This pins a defect that took a site offline. The guard was
# `nonOverlayUplinkNames != [ ] && selectedIsOverlayUplink`, i.e. "skip the
# overlay lane when the site also has a non-overlay uplink". It asked the wrong
# question, and it depended on `topo.uplinkNames` still being populated at this
# stage; when that set is empty the guard fails open and installs the default
# anyway.
#
# On the cobalt candidate that installed `0.0.0.0/0` on an overlay-terminating
# core whose only adjacency was the upstream selector. The selector offers no
# default back, so the router kept reaching the internet on its own egress while
# every client behind it was blackholed -- a router-only health check passes and
# the site is down.
#
# The topology below is that shape, including the empty `uplinkNames` that made
# the old guard fail open. The negative case must report no installable default
# plan; the positive control proves the check is discriminating and not simply
# refusing every default.

repo_root="$(git rev-parse --show-toplevel)"
source "${repo_root}/tests/lib/timing.sh"

start_ms="$(test_now_ms)"
tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

expr_nix="${tmpdir}/fs315-generic-default-lane.nix"
result_json="${tmpdir}/fs315-generic-default-lane.json"

cat >"${expr_nix}" <<'NIX'
let
  repoRoot = builtins.getEnv "REPO_ROOT";
  flake = builtins.getFlake ("path:" + repoRoot);
  lib = flake.inputs.nixpkgs.lib;

  defaultRoutes = import (repoRoot + "/implementation/lib/routing/default-routes.nix") {
    inherit lib;
    self = { outPath = repoRoot; };
  };
  staticContext = import (repoRoot + "/implementation/lib/routing/static/context.nix") {
    inherit lib;
    self = { outPath = repoRoot; };
  };

  mkLink =
    {
      left,
      right,
      uplink,
    }:
    {
      kind = "p2p";
      members = [
        left
        right
      ];
      endpoints = {
        ${left} = {
          node = left;
          interface = "p2p-${left}-${right}";
          addr4 = "10.1.0.0/31";
        };
        ${right} = {
          node = right;
          interface = "p2p-${left}-${right}";
          addr4 = "10.1.0.1/31";
        };
      };
      laneMeta = {
        kind = "uplink";
        uplink = uplink;
        uplinks = [ uplink ];
      };
    };

  # `wan-core` offers a default on `wan`; the overlay core offers nothing, so the
  # `garnet` lane names an uplink with no default in either family.
  mkSite =
    {
      uplinkNames,
      garnetDefault ? false,
    }:
    let
      nodes = {
        sel = {
          role = "upstream-selector";
          uplinks = { };
          attachments = [ ];
        };
        wan-core = {
          role = "core";
          uplinks.wan = {
            ipv4 = [ "0.0.0.0/0" ];
            egress.ipv4.translation.mode = "nat44";
          };
          attachments = [ ];
        };
        ovl-core = {
          role = "core";
          # An overlay-terminating core that anchors no external uplink.
          uplinks = lib.optionalAttrs garnetDefault {
            garnet = {
              ipv4 = [ "0.0.0.0/0" ];
            };
          };
          attachments = [ ];
        };
        access-a = {
          role = "access";
          uplinks = { };
          attachments = [
            {
              kind = "tenant";
              name = "t";
            }
          ];
        };
      };
    in
    {
      inherit nodes;
      inherit uplinkNames;
      uplinkCoreNames = [ "wan-core" ];
      policyNodeName = null;
      upstreamSelectorNodeName = "sel";
      coreNodeNames = [
        "ovl-core"
        "wan-core"
      ];
      overlayReachability = {
        garnet = {
          overlay = "garnet";
          peerSite = null;
          peerSites = [ ];
          terminateOn = [ "ovl-core" ];
          underlayAccess = null;
          routes4 = [ ];
          routes6 = [ ];
        };
      };
      links = {
        # access-a reaches the selector on the `wan` lane, which DOES offer a
        # default. This is the positive control.
        p2p-access-a-sel = mkLink {
          left = "access-a";
          right = "sel";
          uplink = "wan";
        };
        # ovl-core's ONLY adjacency; the `garnet` lane offers no default.
        p2p-ovl-core-sel = mkLink {
          left = "ovl-core";
          right = "sel";
          uplink = "garnet";
        };
        p2p-sel-wan-core = mkLink {
          left = "sel";
          right = "wan-core";
          uplink = "wan";
        };
      };
    };

  planFor =
    site: nodeName:
    let
      ctx = staticContext.build site;
    in
    (defaultRoutes.apply {
      topo = site;
      inherit nodeName;
      node = site.nodes.${nodeName};
      inherit (ctx) routeContext routeFacts routeGraph nonOverlayTransitGraph;
    }).nearestUplinkCoreDefaultPlan;

  # The fail-open condition: the site reports no uplink names at all, so the old
  # `nonOverlayUplinkNames != [ ]` precondition is false.
  overflowing = mkSite { uplinkNames = [ ]; };

  # Positive control: same shape, but the overlay uplink genuinely offers a
  # default, so a default towards it IS authorized.
  garnetIsEgress = mkSite {
    uplinkNames = [ ];
    garnetDefault = true;
  };
in
{
  overlayCorePlan = planFor overflowing "ovl-core";
  accessPlan = planFor overflowing "access-a";
  garnetEgressPlan = planFor garnetIsEgress "ovl-core";
  overlayCoreLaneUplinkHasNoDefault =
    !(builtins.hasAttr "garnet" (staticContext.build overflowing).routeFacts.uplinkHasDefault4Set or { });
  wanLaneUplinkHasDefault =
    builtins.hasAttr "wan" (staticContext.build overflowing).routeFacts.uplinkHasDefault4Set or { };
}
NIX

REPO_ROOT="${repo_root}" nix eval --impure --json --file "${expr_nix}" >"${result_json}"

jq -e '
  # The overlay-terminating core must get no installable generic default: its
  # only lane names an uplink that offers none.
  ((.overlayCorePlan | length) == 0)
  # Positive control 1: a lane whose uplink does offer a default still gets one.
  and ((.accessPlan | length) > 0)
  # Positive control 2: an overlay that IS the modeled egress may carry a
  # default, so the rule is "does the uplink offer a default", not "is it an
  # overlay".
  and ((.garnetEgressPlan | length) > 0)
  # Sanity on the modelled fact the rule reads.
  and (.overlayCoreLaneUplinkHasNoDefault == true)
  and (.wanLaneUplinkHasDefault == true)
' "${result_json}" >/dev/null

elapsed_ms=$(( $(test_now_ms) - start_ms ))
printf 'ok: fs-315 generic default installs only on a lane that offers one (%sms)\n' "${elapsed_ms}"
