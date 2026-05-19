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
  def iface($node; $iface):
    .enterprise.esp.site.hetz.nodes[$node].interfaces[$iface];

  iface("hetz-router-access-dmz"; "tenant-dmz").addr4 == "10.90.10.1/24"
  and iface("hetz-router-access-dmz"; "tenant-dmz").addr6 == "fd42:dead:cafe:10:0:0:0:1/64"
  and iface("hetz-router-access-client"; "tenant-client").addr4 == "10.90.20.1/24"
  and iface("hetz-router-access-client"; "tenant-client").addr6 == "fd42:dead:cafe:20:0:0:0:1/64"
  and iface("hetz-router-access-dmz"; "tenant-dmz").subnet4 == "10.90.10.0/24"
  and iface("hetz-router-access-dmz"; "tenant-dmz").subnet6 == "fd42:dead:cafe:0010:0000:0000:0000:0000/64"
' "${output_json}" >/dev/null || {
  echo "FAIL access-tenant-gateway-host-addresses" >&2
  jq '.enterprise.esp.site.hetz.nodes
    | {
        dmz: ."hetz-router-access-dmz".interfaces."tenant-dmz",
        client: ."hetz-router-access-client".interfaces."tenant-client"
      }' "${output_json}" >&2
  exit 1
}

pass_timed "access-tenant-gateway-host-addresses" "${start_ms}"
