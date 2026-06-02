#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: SMT-NFM-FS300-FS500-OVERLAY-SOURCE-LANE-001
# GAMP-SCOPE: software-module-test

repo_root="$(git rev-parse --show-toplevel)"
source "${repo_root}/tests/lib/timing.sh"

archive_json="$(mktemp)"
output_json="$(mktemp)"
trap 'rm -f "${archive_json}" "${output_json}"' EXIT

nix flake archive --json "path:${repo_root}" >"${archive_json}"
labs_root="$(jq -er '.inputs["network-labs"].path' "${archive_json}")"
intent="${labs_root}/examples/s-router-overlay-dns-lane-policy/intent.nix"

start_ms="$(test_now_ms)"
nix run "${repo_root}#compile-and-build-forwarding-model" -- "${intent}" >"${output_json}"
pass_timed "overlay-route-source-lane-contract:compile" "${start_ms}"

jq -e '
  .enterprise.esp0xdeadbeef.site["site-a"] as $site
  | def has_route($node; $iface; $family; $dst; $access):
      (($site.nodes[$node].interfaces[$iface].routes[$family] // [])
        | any(
            .dst == $dst
            and (.proto // null) == "internal"
            and (.intent.kind // null) == "overlay-reachability"
            and (.overlay // null) == "east-west"
            and (.peerSite // null) == "espbranch.site-b"
            and (.lane.access // null) == $access
            and (.lane.uplink // null) == "east-west"
          ));
  def missing_lane_route($node; $family):
      [
        $site.nodes[$node].interfaces
        | to_entries[]
        | (.value.routes[$family] // [])[]
        | select(
            (.intent.kind // null) == "overlay-reachability"
            and (.proto // null) == "internal"
            and (.overlay // null) == "east-west"
            and (.peerSite // null) == "espbranch.site-b"
            and ((.lane.access // null) == null or (.lane.uplink // null) != "east-west")
          )
      ] | length;
  def forbidden_access_count($node; $family):
      [
        $site.nodes[$node].interfaces
        | to_entries[]
        | (.value.routes[$family] // [])[]
        | select(
            (.intent.kind // null) == "overlay-reachability"
            and (.proto // null) == "internal"
            and (.overlay // null) == "east-west"
            and (.peerSite // null) == "espbranch.site-b"
            and ((.lane.access // null) == "s-router-access-dmz"
              or (.lane.access // null) == "s-router-access-streaming")
          )
      ] | length;
  has_route(
    "s-router-downstream-selector";
    "p2p-s-router-downstream-selector-s-router-policy-only--access-s-router-access-client";
    "ipv4";
    "10.60.10.0/24";
    "s-router-access-client")
  and has_route(
    "s-router-downstream-selector";
    "p2p-s-router-downstream-selector-s-router-policy-only--access-s-router-access-client";
    "ipv6";
    "fd42:dead:feed:0010:0000:0000:0000:0000/64";
    "s-router-access-client")
  and has_route(
    "s-router-policy-only";
    "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-client--uplink-east-west";
    "ipv4";
    "10.60.10.0/24";
    "s-router-access-client")
  and has_route(
    "s-router-policy-only";
    "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-client--uplink-east-west";
    "ipv6";
    "fd42:dead:feed:0010:0000:0000:0000:0000/64";
    "s-router-access-client")
  and missing_lane_route("s-router-downstream-selector"; "ipv4") == 0
  and missing_lane_route("s-router-downstream-selector"; "ipv6") == 0
  and missing_lane_route("s-router-policy-only"; "ipv4") == 0
  and missing_lane_route("s-router-policy-only"; "ipv6") == 0
  and forbidden_access_count("s-router-downstream-selector"; "ipv4") == 0
  and forbidden_access_count("s-router-downstream-selector"; "ipv6") == 0
' "${output_json}" >/dev/null || {
  echo "FAIL overlay-route-source-lane-contract: remote overlay reachability must preserve source access lane and exclude disallowed access lanes" >&2
  jq '
    .enterprise.esp0xdeadbeef.site["site-a"].nodes
    | {
        downstream: ."s-router-downstream-selector".interfaces,
        policy: ."s-router-policy-only".interfaces
      }
    | .. | objects
    | select((.intent.kind // null) == "overlay-reachability" and (.peerSite // null) == "espbranch.site-b")
  ' "${output_json}" >&2
  exit 1
}

pass_timed "overlay-route-source-lane-contract"
