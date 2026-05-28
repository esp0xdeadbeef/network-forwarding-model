#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: SMT-NFM-P2P-UNDERLAY-RETURN-001
# GAMP-SCOPE: software-module-test

repo_root="$(git rev-parse --show-toplevel)"
source "${repo_root}/tests/lib/timing.sh"
output_json="$(mktemp)"
trap 'rm -f "${output_json}"' EXIT

start_ms="$(test_now_ms)"
labs_path="${NETWORK_LABS_PATH:-/home/deadbeef/github/network-labs}"
intent_path="${labs_path}/examples/s-router-overlay-dns-lane-policy/intent.nix"

nix run "${repo_root}#compile-and-build-forwarding-model" -- "${intent_path}" \
  | jq -c . >"${output_json}"

jq -e '
  def has_route($node; $iface; $dst; $via):
    .enterprise.esp0xdeadbeef.site["site-c"].nodes[$node].interfaces[$iface].routes.ipv4
    | any(.dst == $dst and .via4 == $via and .proto == "internal" and .intent.kind == "internal-reachability");
  def has_connected($node; $iface; $dst):
    .enterprise.esp0xdeadbeef.site["site-c"].nodes[$node].interfaces[$iface].routes.ipv4
    | any(.dst == $dst and .proto == "connected" and .intent.kind == "connected-reachability");
  def peer4($link; $node):
    .enterprise.esp0xdeadbeef.site["site-c"].links[$link].endpoints[$node].addr4 | split("/")[0];

  has_route(
    "c-router-policy";
    "p2p-c-router-policy-c-router-upstream-selector--access-c-router-access-dmz--uplink-east-west";
    "10.80.0.10/31";
    peer4(
      "p2p-c-router-policy-c-router-upstream-selector--access-c-router-access-dmz--uplink-east-west";
      "c-router-upstream-selector"
    )
  )
  and has_connected(
    "c-router-downstream-selector";
    "p2p-c-router-downstream-selector-c-router-policy--access-c-router-access-dmz";
    "10.80.0.8/31"
  )
  and (
    [
      .enterprise.esp0xdeadbeef.site["site-c"].nodes[]?.interfaces[]?.routes.ipv4[]?
      | select(.dst == "10.80.0.0/24" and .proto == "internal" and .intent.kind == "internal-reachability")
    ]
    | length == 0
  )
' "${output_json}" >/dev/null || {
  echo "FAIL p2p-specific-underlay-return-routes" >&2
  jq -r '
    .enterprise.esp0xdeadbeef.site["site-c"].nodes as $nodes
    | {
        policy: $nodes."c-router-policy".interfaces
          | to_entries[]
          | select(.key | contains("uplink-east-west"))
          | {interface: .key, routes: [.value.routes.ipv4[]? | select(.dst | startswith("10.80.0."))]},
        downstream: $nodes."c-router-downstream-selector".interfaces
          | to_entries[]
          | select(.key | contains("access-c-router-access-dmz"))
          | {interface: .key, routes: [.value.routes.ipv4[]? | select(.dst | startswith("10.80.0."))]}
      }
  ' "${output_json}" >&2
  exit 1
}

pass_timed "p2p-specific-underlay-return-routes" "${start_ms}"
