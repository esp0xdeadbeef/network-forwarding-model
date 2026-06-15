#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-370-HDS-010-SDS-010-SMS-020
# GAMP-SCOPE: software-module-test

repo_root="$(git rev-parse --show-toplevel)"
source "${repo_root}/tests/lib/timing.sh"

output_json="$(mktemp)"
trap 'rm -f "${output_json}"' EXIT

intent="${repo_root}/tests/fixtures/examples/s-router-overlay-dns-lane-policy/intent.nix"

start_ms="$(test_now_ms)"
nix run "${repo_root}#compile-and-build-forwarding-model" -- "${intent}" >"${output_json}"
pass_timed "fs370-overlay-source-prefix-identity-binding:compile" "${start_ms}"

jq -e '
  .enterprise.espbranch.site["site-b"] as $remote
  | .enterprise.esp0xdeadbeef.site["site-a"] as $local
  | def has_route($node; $iface; $family; $dst; $access; $uplink):
      (($local.nodes[$node].interfaces[$iface].routes[$family] // [])
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
        $local.nodes[$node].interfaces
        | to_entries[]
        | (.value.routes.ipv4[]?, .value.routes.ipv6[]?)
        | select(
            (.intent.kind // null) == "overlay-reachability"
            and (.overlay // null) == "east-west"
            and (.peerSite // null) == "espbranch.site-b"
            and ((.lane.access // null) == null or (.lane.uplink // null) == null)
          )
      ] | length;
  ($remote.tenantPrefixOwners["4|10.70.10.0/24"].owner == "b-router-access-hostile")
  and ($remote.tenantPrefixOwners["6|fd42:dead:feed:0070:0000:0000:0000:0000/64"].owner == "b-router-access-hostile")
  and ($remote.tenantPrefixOwners["6|source:/run/secrets/access-node-ipv6-prefix-espbranch-site-b-b-router-access-hostile"].owner == "b-router-access-hostile")
  and has_route(
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
    "fd42:dead:feed:0010:0000:0000:0000:0000/64";
    "s-router-access-client";
    "east-west")
  and has_route(
    "s-router-policy-only";
    "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-client--uplink-east-west";
    "ipv4";
    "10.60.10.0/24";
    "s-router-access-client";
    "east-west")
  and has_route(
    "s-router-policy-only";
    "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-client--uplink-east-west";
    "ipv6";
    "fd42:dead:feed:0010:0000:0000:0000:0000/64";
    "s-router-access-client";
    "east-west")
  and missing_lane_count("s-router-downstream-selector") == 0
  and missing_lane_count("s-router-policy-only") == 0
' "${output_json}" >/dev/null || {
  echo "FAIL fs370-overlay-source-prefix-identity-binding: NFM must bind overlay source-prefix identity to structured owner and lane metadata before CPM" >&2
  jq '
    {
      remoteOwners: .enterprise.espbranch.site["site-b"].tenantPrefixOwners,
      localRoutes: [
        .enterprise.esp0xdeadbeef.site["site-a"].nodes
        | to_entries[]
        | . as $node
        | ($node.value.interfaces // {})
        | to_entries[]
        | (.value.routes.ipv4[]?, .value.routes.ipv6[]?)
        | select(
            (.intent.kind // null) == "overlay-reachability"
            and (.overlay // null) == "east-west"
            and (.peerSite // null) == "espbranch.site-b"
          )
        | { node: $node.key, route: . }
      ]
    }
  ' "${output_json}" >&2
  exit 1
}

pass_timed "fs370-overlay-source-prefix-identity-binding"
