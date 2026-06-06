#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-380-HDS-010-SDS-010-SMS-010
# GAMP-ID: FS-370-HDS-010-SDS-010-SMS-040
# GAMP-SCOPE: software-module-test

repo_root="$(git rev-parse --show-toplevel)"
source "${repo_root}/tests/lib/timing.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

archive_json="${tmpdir}/archive.json"
output_json="${tmpdir}/out.json"

nix flake archive --json "path:${repo_root}" >"${archive_json}"
labs_root="$(jq -er '.inputs["network-labs"].path' "${archive_json}")"
intent="${labs_root}/examples/s-router-overlay-dns-lane-policy/intent.nix"

start_ms="$(test_now_ms)"
nix run "${repo_root}#compile-and-build-forwarding-model" -- "${intent}" >"${output_json}"
pass_timed "fs380-ordinary-wan-return-route-lane:compile" "${start_ms}"

jq -e '
  def route_count($site; $node; $iface; $dst):
    [
      $site.nodes[$node].interfaces[$iface].routes.ipv4[]?
      | select(
          (.dst // null) == $dst
          and (.proto // null) == "internal"
          and (.intent.kind // null) == "internal-reachability"
        )
    ] | length;

  .enterprise.esp0xdeadbeef.site["site-a"] as $siteA
  | .enterprise.espbranch.site["site-b"] as $siteB
  | "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-client--uplink-east-west" as $siteAEastWest
  | "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-client--uplink-isp-a" as $siteAIspA
  | "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-client--uplink-isp-b" as $siteAIspB
  | "p2p-b-router-policy-b-router-upstream-selector--access-b-router-access-branch--uplink-east-west" as $siteBEastWest
  | "p2p-b-router-policy-b-router-upstream-selector--access-b-router-access-branch--uplink-wan" as $siteBWan
  | route_count($siteA; "s-router-upstream-selector"; $siteAEastWest; "10.20.20.0/24") == 0
  and (
    route_count($siteA; "s-router-upstream-selector"; $siteAIspA; "10.20.20.0/24")
    + route_count($siteA; "s-router-upstream-selector"; $siteAIspB; "10.20.20.0/24")
  ) >= 1
  and route_count($siteB; "b-router-upstream-selector"; $siteBEastWest; "10.60.10.0/24") == 0
  and route_count($siteB; "b-router-upstream-selector"; $siteBWan; "10.60.10.0/24") >= 1
' "${output_json}" >/dev/null || {
  echo "FAIL fs380-ordinary-wan-return-route-lane: ordinary WAN return route must not use the east-west/core-nebula lane" >&2
  jq '
    {
      siteA_access_client: (
        .enterprise.esp0xdeadbeef.site["site-a"].nodes["s-router-upstream-selector"].interfaces
        | to_entries[]
        | select(.key | test("access-s-router-access-client.*uplink-(east-west|isp-a|isp-b)"))
        | { iface: .key, routes: [ .value.routes.ipv4[]? | select((.dst // null) == "10.20.20.0/24") ] }
      ),
      siteB_branch: (
        .enterprise.espbranch.site["site-b"].nodes["b-router-upstream-selector"].interfaces
        | to_entries[]
        | select(.key | test("access-b-router-access-branch.*uplink-(east-west|wan)"))
        | { iface: .key, routes: [ .value.routes.ipv4[]? | select((.dst // null) == "10.60.10.0/24") ] }
      )
    }
  ' "${output_json}" >&2
  exit 1
}

pass_timed "fs380-ordinary-wan-return-route-lane"
