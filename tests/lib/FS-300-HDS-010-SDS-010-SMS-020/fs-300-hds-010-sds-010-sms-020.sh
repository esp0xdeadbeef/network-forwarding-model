#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-300-HDS-010-SDS-010-SMS-020
# GAMP-SCOPE: software-module-test

repo_root="$(git rev-parse --show-toplevel)"
source "${repo_root}/tests/lib/timing.sh"

output_json="$(mktemp)"
trap 'rm -f "${output_json}"' EXIT

intent="${repo_root}/tests/fixtures/examples/s-router-overlay-dns-lane-policy/intent.nix"

start_ms="$(test_now_ms)"
nix run "${repo_root}#compile-and-build-forwarding-model" -- "${intent}" >"${output_json}"
pass_timed "fs300-source-lane-route-metadata:compile" "${start_ms}"

jq -e '
  .enterprise.esp0xdeadbeef.site["site-a"] as $site
  | def source_scoped_overlay_routes($node):
      $site.nodes[$node].interfaces
      | to_entries[]
      | (.value.routes.ipv4[]?, .value.routes.ipv6[]?)
      | select(
          (.proto // null) == "internal"
          and (.intent.kind // null) == "overlay-reachability"
          and (.overlay // null) == "east-west"
          and (.peerSite // null) == "espbranch.site-b"
        );
    def has_route($node; $iface; $family; $dst; $access; $uplink):
      (($site.nodes[$node].interfaces[$iface].routes[$family] // [])
        | any(
            .dst == $dst
            and (.proto // null) == "internal"
            and (.intent.kind // null) == "overlay-reachability"
            and (.overlay // null) == "east-west"
            and (.peerSite // null) == "espbranch.site-b"
            and (.lane.access // null) == $access
            and (.lane.uplink // null) == $uplink
          ));
    def missing_lane_count($node):
      [
        source_scoped_overlay_routes($node)
        | select((.lane.access // null) == null or (.lane.uplink // null) == null)
      ] | length;
    has_route(
      "s-router-downstream-selector";
      "p2p-s-router-downstream-selector-s-router-policy-only--access-s-router-access-client";
      "ipv4";
      "10.60.10.0/24";
      "s-router-access-client";
      "east-west")
    and has_route(
      "s-router-downstream-selector";
      "p2p-s-router-downstream-selector-s-router-policy-only--access-s-router-access-client";
      "ipv6";
      "fd42:dead:feed:10::/64";
      "s-router-access-client";
      "east-west")
    and has_route(
      "s-router-policy-only";
      "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-client";
      "ipv4";
      "10.60.10.0/24";
      "s-router-access-client";
      "east-west")
    and has_route(
      "s-router-policy-only";
      "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-client";
      "ipv6";
      "fd42:dead:feed:10::/64";
      "s-router-access-client";
      "east-west")
    and missing_lane_count("s-router-downstream-selector") == 0
    and missing_lane_count("s-router-policy-only") == 0
' "${output_json}" >/dev/null || {
  echo "FAIL fs300-source-lane-route-metadata: source-scoped overlay routes must carry structured lane.access and lane.uplink metadata" >&2
  jq '
    .enterprise.esp0xdeadbeef.site["site-a"].nodes
    | to_entries[]
    | {
        node: .key,
        routes: [
          .value.interfaces
          | to_entries[]
          | {
              iface: .key,
              route: (.value.routes.ipv4[]?, .value.routes.ipv6[]?)
            }
          | select(
              (.route.intent.kind // null) == "overlay-reachability"
              and (.route.overlay // null) == "east-west"
              and (.route.peerSite // null) == "espbranch.site-b"
            )
        ]
      }
    | select(.routes != [])
  ' "${output_json}" >&2
  exit 1
}

pass_timed "fs300-source-lane-route-metadata"
