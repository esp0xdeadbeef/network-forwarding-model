#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-370-HDS-010-SDS-010-SMS-040
# GAMP-SCOPE: software-module-test

repo_root="$(git rev-parse --show-toplevel)"
source "${repo_root}/tests/lib/timing.sh"

output_json="$(mktemp)"
trap 'rm -f "${output_json}"' EXIT

intent="${repo_root}/tests/fixtures/examples/s-router-overlay-dns-lane-policy/intent.nix"

start_ms="$(test_now_ms)"
nix run "${repo_root}#compile-and-build-forwarding-model" -- "${intent}" >"${output_json}"
pass_timed "fs370-unrelated-egress-route-denial:compile" "${start_ms}"

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
    def forbidden_count($node):
      [
        source_scoped_overlay_routes($node)
        | select(
            (.lane.access // null) == "s-router-access-dmz"
            or (.lane.access // null) == "s-router-access-streaming"
            or (.lane.uplink // null) != "east-west"
            or (.lane.access // null) == null
          )
      ] | length;
    def required_access_count($node):
      [
        source_scoped_overlay_routes($node)
        | select((.lane.access // null) == "s-router-access-client" and (.lane.uplink // null) == "east-west")
      ] | length;
    required_access_count("s-router-downstream-selector") >= 2
    and required_access_count("s-router-policy-only") >= 2
    and forbidden_count("s-router-downstream-selector") == 0
    and forbidden_count("s-router-policy-only") == 0
' "${output_json}" >/dev/null || {
  echo "FAIL fs370-unrelated-egress-route-denial: NFM must reject unrelated egress lanes and destination-only fallback routes for east-west overlay reachability" >&2
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

pass_timed "fs370-unrelated-egress-route-denial"
