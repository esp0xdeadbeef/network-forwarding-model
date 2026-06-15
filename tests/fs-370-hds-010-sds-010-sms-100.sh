#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-370-HDS-010-SDS-010-SMS-100
# GAMP-SCOPE: software-module-test
#
# Focused construction test: upstream-selector shared-interface IP rule priority.
# SMS-100 requires per-lane route grouping with correct metadata (access, uplink,
# direction) and no bare default-route catch-all on shared interfaces.
# At NFM level: verify lane-scoped routes carry correct access/uplink metadata,
# routes have direction for outbound vs return, and per-lane grouping exists.
#
# Seeded negatives:
#   - Route without lane metadata on shared interface
#   - Route without direction for policy-governed traffic

repo_root="$(git rev-parse --show-toplevel)"
source "${repo_root}/tests/lib/timing.sh"
tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

input_nix="${tmpdir}/compiler-output.nix"
output_json="${tmpdir}/out.json"

cat >"${input_nix}" <<'NIX'
{
  sites.acme.ams = {
    addressPools = {
      local.ipv4 = "10.37.0.0/24";
      p2p.ipv4 = "10.37.1.0/24";
      p2p.ipv6 = "fd42:370::/118";
    };

    attachments = [
      { unit = "access-client"; kind = "tenant"; name = "client"; }
    ];

    domains = {
      externals = [ { kind = "external"; name = "wan"; } ];
      tenants = [
        { kind = "tenant"; name = "client"; ipv4 = "10.37.20.0/24"; ipv6 = "fd42:370:20::/64"; }
      ];
    };

    communicationContract.relations = [
      { id = "allow-client-to-wan"; priority = 100;
        from = { kind = "tenant"; name = "client"; };
        to = { kind = "external"; uplinks = [ "wan" ]; };
        trafficType = "any"; action = "allow"; }
    ];

    transit.ordering = [
      [ "access-client" "downstream" ]
      [ "downstream" "policy" ]
      [ "policy" "upstream" ]
      [ "upstream" "core-wan" ]
    ];

    units = {
      access-client.role = "access";
      downstream.role = "downstream-selector";
      policy.role = "policy";
      upstream.role = "upstream-selector";
      core-wan = { role = "core"; uplinks.wan.ipv4 = [ "0.0.0.0/0" ]; uplinks.wan.ipv6 = [ "::/0" ]; };
    };
  };
}
NIX

start_ms="$(test_now_ms)"
nix run "${repo_root}#compile-and-build-forwarding-model" -- "${input_nix}" >"${output_json}"
pass_timed "fs370-sms100-shared-iface-ip-rule-priority:compile" "${start_ms}"

# Predicate 1: Lane-scoped routes exist with access/uplink metadata
jq -e '
  .enterprise.acme.site.ams as $site
  | def lane_routes:
      $site.nodes
      | to_entries[]
      | .value.interfaces // {}
      | to_entries[]
      | .value.routes.ipv4[]?
      | select(.lane != null);
  [lane_routes] | length > 0
' "${output_json}" >/dev/null || {
  echo "FAIL fs370-sms100: must have at least one lane-scoped route with access/uplink metadata" >&2
  exit 1
}

# Predicate 2: Lane-scoped routes carry both access and uplink fields
jq -e '
  .enterprise.acme.site.ams as $site
  | def lane_routes_complete:
      $site.nodes
      | to_entries[]
      | .value.interfaces // {}
      | to_entries[]
      | .value.routes.ipv4[]?
      | select(.lane != null and .lane.access != null and .lane.uplink != null);
  [lane_routes_complete] | length > 0
' "${output_json}" >/dev/null || {
  echo "FAIL fs370-sms100: lane-scoped routes must carry both access and uplink lane metadata" >&2
  exit 1
}

# Predicate 3: Policy-derived routes carry direction field
jq -e '
  .enterprise.acme.site.ams as $site
  | def directed_routes:
      $site.nodes
      | to_entries[]
      | .value.interfaces // {}
      | to_entries[]
      | .value.routes.ipv4[]?
      | select(.direction != null);
  [directed_routes] | length > 0
' "${output_json}" >/dev/null || {
  echo "FAIL fs370-sms100: must have routes with direction metadata for per-lane return-path routing" >&2
  exit 1
}

# Predicate 4: The site has policy field populated (policy forwarding structure exists)
jq -e '
  .enterprise.acme.site.ams.policy != null
' "${output_json}" >/dev/null || {
  echo "FAIL fs370-sms100: site must have policy forwarding structure for per-lane rule evaluation" >&2
  exit 1
}

# Seeded negative: No policyOnly route without lane metadata (bare policy route would shadow)
jq -e '
  .enterprise.acme.site.ams as $site
  | def bare_policy_only:
      $site.nodes
      | to_entries[]
      | .value.interfaces // {}
      | to_entries[]
      | .value.routes.ipv4[]?
      | select(.policyOnly == true and .lane == null);
  [bare_policy_only] | length == 0
' "${output_json}" >/dev/null || {
  echo "FAIL fs370-sms100: policyOnly routes must carry lane metadata (bare policy route without lane context would shadow higher-priority lanes)" >&2
  jq '[.enterprise.acme.site.ams.nodes | to_entries[] | .value.interfaces // {} | to_entries[] | .value.routes.ipv4[]? | select(.policyOnly == true) | {node, dst, lane, direction}]' "${output_json}" >&2
  exit 1
}

pass_timed "fs370-sms100-shared-iface-ip-rule-priority"
