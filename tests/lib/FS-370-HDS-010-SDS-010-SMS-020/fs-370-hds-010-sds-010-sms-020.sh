#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-370-HDS-010-SDS-010-SMS-020
# GAMP-SCOPE: software-module-test

repo_root="$(git rev-parse --show-toplevel)"
source "${repo_root}/tests/lib/timing.sh"

tmpdir="$(mktemp -d)"
output_json="${tmpdir}/output.json"
trap 'rm -rf "${tmpdir}"' EXIT

intent="${repo_root}/tests/fixtures/examples/s-router-overlay-dns-lane-policy/intent.nix"

expect_compile_failure() {
  local name="$1"
  local fixture="$2"
  shift 2

  local out_file="${tmpdir}/${name}.out"
  local err_file="${tmpdir}/${name}.err"
  local start_ms
  start_ms="$(test_now_ms)"

  if nix run "${repo_root}#compile-and-build-forwarding-model" -- "${fixture}" >"${out_file}" 2>"${err_file}"; then
    echo "FAIL ${name}: expected compile failure" >&2
    jq '.' "${out_file}" >&2 || cat "${out_file}" >&2
    exit 1
  fi

  local pattern
  for pattern in "$@"; do
    if ! rg -q -- "${pattern}" "${err_file}"; then
      echo "FAIL ${name}: missing expected diagnostic pattern: ${pattern}" >&2
      sed -n '1,160p' "${err_file}" >&2
      exit 1
    fi
  done

  pass_timed "${name}" "${start_ms}"
}

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

unbound_overlay_prefix_intent="${tmpdir}/unbound-overlay-prefix.nix"
cat >"${unbound_overlay_prefix_intent}" <<EOF
let
  base = import ${intent};
  siteA = base.esp0xdeadbeef."site-a";
  overlays =
    map
      (
        overlay:
          if (overlay.name or null) == "east-west" then
            overlay // {
              prefixes = {
                ipv4 = [ "198.18.222.0/24" ];
                ipv6 = [ "2001:db8:370::/64" ];
              };
            }
          else
            overlay
      )
      siteA.transport.overlays;
in
base // {
  esp0xdeadbeef = base.esp0xdeadbeef // {
    "site-a" = siteA // {
      transport = siteA.transport // {
        inherit overlays;
      };
    };
  };
}
EOF

expect_compile_failure \
  "fs370-overlay-source-prefix-identity-binding:seeded-negative-unbound-prefix" \
  "${unbound_overlay_prefix_intent}" \
  "overlay-source-prefix-unbound" \
  "east-west" \
  "198\\.18\\.222\\.0/24" \
  "2001:db8:370::/64"

conflicting_prefix_owner_intent="${tmpdir}/conflicting-prefix-owner.nix"
cat >"${conflicting_prefix_owner_intent}" <<EOF
let
  base = import ${intent};
  siteB = base.espbranch."site-b";
  prefixes =
    map
      (
        prefix:
          if (prefix.name or null) == "branch" then
            prefix // {
              ipv4 = "10.70.10.0/24";
            }
          else
            prefix
      )
      siteB.ownership.prefixes;
in
base // {
  espbranch = base.espbranch // {
    "site-b" = siteB // {
      ownership = siteB.ownership // {
        inherit prefixes;
      };
    };
  };
}
EOF

expect_compile_failure \
  "fs370-overlay-source-prefix-identity-binding:seeded-negative-conflicting-prefix" \
  "${conflicting_prefix_owner_intent}" \
  "10\\.70\\.10\\.0/24" \
  "branch" \
  "hostile"
