#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
source "${repo_root}/tests/lib/timing.sh"
output_json="$(mktemp)"
trap 'rm -f "${output_json}"' EXIT

start_ms="$(test_now_ms)"
labs_path="${NETWORK_LABS_PATH:-/home/deadbeef/github/network-labs}"
intent_path="${labs_path}/labs/lab-s-sigma/s-router-test-three-site/intent.nix"

nix run "${repo_root}#compile-and-build-forwarding-model" -- "${intent_path}" \
  | jq -c . >"${output_json}"

jq -e '
  def has_route($node; $iface; $dst; $via):
    .enterprise.esp.site.hetz.nodes[$node].interfaces[$iface].routes.ipv4
    | any(.dst == $dst and .via4 == $via and .proto == "internal" and .intent.kind == "internal-reachability");

  has_route(
    "hetz-router-policy";
    "p2p-hetz-router-policy-hetz-router-upstream--access-hetz-router-access-dmz--uplink-east-west";
    "10.80.0.10/31";
    "10.80.0.15"
  )
  and has_route(
    "hetz-router-downstream";
    "p2p-hetz-router-downstream-hetz-router-policy--access-hetz-router-access-dmz";
    "10.80.0.10/31";
    "10.80.0.9"
  )
  and (
    [
      .enterprise.esp.site.hetz.nodes[]?.interfaces[]?.routes.ipv4[]?
      | select(.dst == "10.80.0.0/24" and .proto == "internal" and .intent.kind == "internal-reachability")
    ]
    | length == 0
  )
' "${output_json}" >/dev/null || {
  echo "FAIL p2p-specific-underlay-return-routes" >&2
  jq -r '
    .enterprise.esp.site.hetz.nodes
    | {
        policy: ."hetz-router-policy".interfaces
          | to_entries[]
          | select(.key | contains("uplink-east-west"))
          | {interface: .key, routes: [.value.routes.ipv4[]? | select(.dst | startswith("10.80.0."))]},
        downstream: ."hetz-router-downstream".interfaces
          | to_entries[]
          | select(.key | contains("access-hetz-router-access-dmz"))
          | {interface: .key, routes: [.value.routes.ipv4[]? | select(.dst | startswith("10.80.0."))]}
      }
  ' "${output_json}" >&2
  exit 1
}

pass_timed "p2p-specific-underlay-return-routes" "${start_ms}"
