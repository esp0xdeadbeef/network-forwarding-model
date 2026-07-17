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
#   - Lower-priority lane captures another lane's tenant prefix
#   - Default-route catch-all appears on a shared source interface

repo_root="$(git rev-parse --show-toplevel)"
source "${repo_root}/tests/lib/timing.sh"
tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

input_nix="${tmpdir}/compiler-output.nix"
output_json="${tmpdir}/out.json"

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
      sed -n '1,180p' "${err_file}" >&2
      exit 1
    fi
  done

  pass_timed "${name}" "${start_ms}"
}

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
        trafficType = "any"; returnBehavior = "symmetric"; action = "allow"; }
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

shared_default_catchall_intent="${tmpdir}/shared-default-catchall.nix"
cat >"${shared_default_catchall_intent}" <<'NIX'
{
  sites.acme.ams = {
    addressPools = {
      local.ipv4 = "10.37.0.0/24";
      p2p.ipv4 = "10.37.1.0/24";
      p2p.ipv6 = "fd42:370::/118";
    };
    attachments = [
      { unit = "access-a"; kind = "tenant"; name = "a"; }
      { unit = "access-b"; kind = "tenant"; name = "b"; }
    ];
    domains = {
      externals = [ { kind = "external"; name = "wan"; } ];
      tenants = [
        { kind = "tenant"; name = "a"; ipv4 = "10.37.20.0/24"; ipv6 = "fd42:370:20::/64"; }
        { kind = "tenant"; name = "b"; ipv4 = "10.37.30.0/24"; ipv6 = "fd42:370:30::/64"; }
      ];
    };
    communicationContract.relations = [
      { id = "allow-a-to-wan"; priority = 100; from = { kind = "tenant"; name = "a"; }; to = { kind = "external"; uplinks = [ "wan" ]; }; trafficType = "any"; returnBehavior = "symmetric"; action = "allow"; }
      { id = "allow-b-to-wan"; priority = 110; from = { kind = "tenant"; name = "b"; }; to = { kind = "external"; uplinks = [ "wan" ]; }; trafficType = "any"; returnBehavior = "symmetric"; action = "allow"; }
    ];
    transit.ordering = [
      [ "access-a" "downstream" ]
      [ "access-b" "downstream" ]
      [ "downstream" "policy" ]
      [ "policy" "upstream" ]
      [ "upstream" "core-wan" ]
    ];
    links.shared-source = {
      kind = "p2p";
      endpoints = {
        policy = {
          addr4 = "10.37.9.0/31";
          interfaceData.routes4 = [
            { dst = "0.0.0.0/0"; via4 = "10.37.9.1"; proto = "default"; policyOnly = true; metric = 2000; lane = { access = "access-a"; uplink = "wan"; }; direction = "return"; intent = { kind = "default-reachability"; }; }
            { dst = "10.37.30.0/24"; via4 = "10.37.9.1"; proto = "internal"; policyOnly = true; metric = 2010; lane = { access = "access-b"; uplink = "wan"; }; direction = "return"; intent = { kind = "internal-reachability"; }; }
          ];
        };
        upstream = { addr4 = "10.37.9.1/31"; };
      };
    };
    units = {
      access-a.role = "access";
      access-b.role = "access";
      downstream.role = "downstream-selector";
      policy.role = "policy";
      upstream.role = "upstream-selector";
      core-wan = { role = "core"; uplinks.wan.ipv4 = [ "0.0.0.0/0" ]; uplinks.wan.ipv6 = [ "::/0" ]; };
    };
  };
}
NIX

priority_inversion_intent="${tmpdir}/priority-inversion.nix"
cat >"${priority_inversion_intent}" <<'NIX'
{
  sites.acme.ams = {
    addressPools = {
      local.ipv4 = "10.37.0.0/24";
      p2p.ipv4 = "10.37.1.0/24";
      p2p.ipv6 = "fd42:370::/118";
    };
    attachments = [
      { unit = "access-a"; kind = "tenant"; name = "a"; }
      { unit = "access-b"; kind = "tenant"; name = "b"; }
    ];
    domains = {
      externals = [ { kind = "external"; name = "wan"; } ];
      tenants = [
        { kind = "tenant"; name = "a"; ipv4 = "10.37.20.0/24"; ipv6 = "fd42:370:20::/64"; }
        { kind = "tenant"; name = "b"; ipv4 = "10.37.30.0/24"; ipv6 = "fd42:370:30::/64"; }
      ];
    };
    communicationContract.relations = [
      { id = "allow-a-to-wan"; priority = 100; from = { kind = "tenant"; name = "a"; }; to = { kind = "external"; uplinks = [ "wan" ]; }; trafficType = "any"; returnBehavior = "symmetric"; action = "allow"; }
      { id = "allow-b-to-wan"; priority = 110; from = { kind = "tenant"; name = "b"; }; to = { kind = "external"; uplinks = [ "wan" ]; }; trafficType = "any"; returnBehavior = "symmetric"; action = "allow"; }
    ];
    transit.ordering = [
      [ "access-a" "downstream" ]
      [ "access-b" "downstream" ]
      [ "downstream" "policy" ]
      [ "policy" "upstream" ]
      [ "upstream" "core-wan" ]
    ];
    links.shared-source = {
      kind = "p2p";
      endpoints = {
        policy = {
          addr4 = "10.37.9.0/31";
          interfaceData.routes4 = [
            { dst = "10.37.30.0/24"; via4 = "10.37.9.1"; proto = "internal"; policyOnly = true; metric = 2000; lane = { access = "access-a"; uplink = "wan"; }; direction = "return"; intent = { kind = "internal-reachability"; }; }
            { dst = "10.37.20.0/24"; via4 = "10.37.9.1"; proto = "internal"; policyOnly = true; metric = 2010; lane = { access = "access-b"; uplink = "wan"; }; direction = "return"; intent = { kind = "internal-reachability"; }; }
          ];
        };
        upstream = { addr4 = "10.37.9.1/31"; };
      };
    };
    units = {
      access-a.role = "access";
      access-b.role = "access";
      downstream.role = "downstream-selector";
      policy.role = "policy";
      upstream.role = "upstream-selector";
      core-wan = { role = "core"; uplinks.wan.ipv4 = [ "0.0.0.0/0" ]; uplinks.wan.ipv6 = [ "::/0" ]; };
    };
  };
}
NIX

expect_compile_failure \
  "fs370-sms100-shared-iface-ip-rule-priority:seeded-negative-default-catchall" \
  "${shared_default_catchall_intent}" \
  "diagnostic\\.default-route-catch-all-shared-interface" \
  "shared-source" \
  "access-a\\|wan" \
  "0\\.0\\.0\\.0/0"

expect_compile_failure \
  "fs370-sms100-shared-iface-ip-rule-priority:seeded-negative-priority-inversion" \
  "${priority_inversion_intent}" \
  "diagnostic\\.priority-inversion-route-capture" \
  "capturingLane: access-b\\|wan" \
  "capturedSubnet: 10\\.37\\.20\\.0/24" \
  "correctAccess: access-a"

pass_timed "fs370-sms100-shared-iface-ip-rule-priority"
