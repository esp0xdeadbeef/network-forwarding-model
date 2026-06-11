#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-180-HDS-010-SDS-010-SMS-010
# GAMP-ID: FS-180-HDS-010-SDS-010-SMS-020
# GAMP-ID: FS-270-HDS-010-SDS-010-SMS-040
# GAMP-ID: SMT-NFM-FS180-FS270-SELECTOR-RELATION-AUTHORITY-001
# GAMP-SCOPE: software-module-test
#
# Focused construction test: selector lane-default routes carry relationIds
# and direction from modeled allow relations, not from topology alone.
#
# SMS-010 (allow tuple validation): routes carry full relation identity
# SMS-020 (adjacent denial): topology without matching relation produces no routes
# SMS-040 (selector handoff): selector forwarding preserves relation identity
#
# Seeded negatives:
#   - Lane topology exists but no trafficPath authorizes WAN egress for access unit
#   - deny-only relation produces no lane-default routes

repo_root="$(git rev-parse --show-toplevel)"
source "${repo_root}/tests/lib/timing.sh"

start_ms="$(test_now_ms)"
tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

archive_json="${tmpdir}/archive.json"
nix flake archive --json "path:${repo_root}" >"${archive_json}"

compiler_path="$(
  ARCHIVE_JSON="${archive_json}" nix eval --impure --raw --expr '
    let
      archived = builtins.fromJSON (builtins.readFile (builtins.getEnv "ARCHIVE_JSON"));
      compilerPath = archived.inputs."network-compiler".path or null;
    in
      if compilerPath == null then throw "FS-180-FS-270 selector relation authority: missing network-compiler input" else compilerPath
  '
)"

# --- Positive case: trafficPath allows client → wan ---
positive_input="${tmpdir}/positive-relation-authority.nix"
positive_json="${tmpdir}/positive-relation-authority.json"

cat >"${positive_input}" <<'NIX'
{
  esp0xdeadbeef = {
    "site-a" = {
      pools = {
        p2p.ipv4 = "10.10.0.0/24";
        loopback.ipv4 = "10.19.0.0/24";
      };

      ownership.prefixes = [
        { kind = "tenant"; name = "client"; ipv4 = "10.20.20.0/24"; }
      ];

      communicationContract.relations = [
        {
          id = "allow-client-to-wan-https";
          priority = 100;
          from = { kind = "tenant"; name = "client"; };
          to = { kind = "external"; uplinks = [ "wan" ]; };
          trafficType = "any";
          action = "allow";
        }
      ];

      topology.nodes = {
        access-client = {
          role = "access";
          attachments = [ { kind = "tenant"; name = "client"; } ];
        };
        downstream.role = "downstream-selector";
        policy.role = "policy";
        upstream.role = "upstream-selector";
        core-wan = {
          role = "core";
          uplinks.wan.ipv4 = [ "0.0.0.0/0" ];
        };
      };

      topology.links = [
        [ "access-client" "downstream" ]
        [ "downstream" "policy" ]
        [ "policy" "upstream" ]
        [ "upstream" "core-wan" ]
      ];
    };
  };
}
NIX

nix run --no-warn-dirty --no-write-lock-file "path:${compiler_path}#compile" -- \
  "${positive_input}" >"${tmpdir}/compiler-positive.json"

nix run "${repo_root}#compile-and-build-forwarding-model" -- \
  "${positive_input}" >"${positive_json}"

# --- Positive assertions ---
echo "=== Positive case: routes carry relationIds and direction ==="

# Downstream-selector lane route toward policy
jq -e '
  [ .enterprise.esp0xdeadbeef.site."site-a".nodes.downstream.interfaces
    | to_entries[]
    | select(.key | startswith("p2p-downstream-policy"))
    | .value.routes.ipv4[]
    | select(.intent.kind == "default-reachability" and .lane != null)
  ][0]
  | .relationIds == ["allow-client-to-wan-https"]
    and .direction == "outbound"
    and .policyOnly == true
' "${positive_json}" >/dev/null || {
  echo "FAIL: downstream-selector lane route missing relationIds or direction" >&2
  jq '[.enterprise.esp0xdeadbeef.site."site-a".nodes.downstream.interfaces
    | to_entries[]
    | select(.key | startswith("p2p-downstream-policy"))
    | .value.routes.ipv4[]
    | select(.intent.kind == "default-reachability")
    | { relationIds, direction, policyOnly, lane }]' "${positive_json}" >&2
  exit 1
}

# Policy node lane route toward upstream-selector
jq -e '
  [ .enterprise.esp0xdeadbeef.site."site-a".nodes.policy.interfaces
    | to_entries[]
    | select(.key | startswith("p2p-policy-upstream"))
    | .value.routes.ipv4[]
    | select(.intent.kind == "default-reachability" and .lane != null)
  ][0]
  | .relationIds == ["allow-client-to-wan-https"]
    and .direction == "outbound"
    and .policyOnly == true
' "${positive_json}" >/dev/null || {
  echo "FAIL: policy node lane route missing relationIds or direction" >&2
  jq '[.enterprise.esp0xdeadbeef.site."site-a".nodes.policy.interfaces
    | to_entries[]
    | select(.key | startswith("p2p-policy-upstream"))
    | .value.routes.ipv4[]
    | select(.intent.kind == "default-reachability")
    | { relationIds, direction, policyOnly, lane }]' "${positive_json}" >&2
  exit 1
}

# Upstream-selector lane route toward core
jq -e '
  [ .enterprise.esp0xdeadbeef.site."site-a".nodes.upstream.interfaces
    | to_entries[]
    | select(.key | startswith("p2p-core"))
    | .value.routes.ipv4[]
    | select(.intent.kind == "default-reachability" and .lane != null)
  ][0]
  | .relationIds == ["allow-client-to-wan-https"]
    and .direction == "outbound"
    and .policyOnly == true
' "${positive_json}" >/dev/null || {
  echo "FAIL: upstream-selector lane route missing relationIds or direction" >&2
  jq '[.enterprise.esp0xdeadbeef.site."site-a".nodes.upstream.interfaces
    | to_entries[]
    | select(.key | startswith("p2p-core"))
    | .value.routes.ipv4[]
    | select(.intent.kind == "default-reachability")
    | { relationIds, direction, policyOnly, lane }]' "${positive_json}" >&2
  exit 1
}

echo "PASS: positive case — selector routes carry relationIds and direction"

# --- Seeded negative case: topology without matching WAN relation ---
negative_input="${tmpdir}/negative-topology-only.nix"
negative_json="${tmpdir}/negative-topology-only.json"

cat >"${negative_input}" <<'NIX'
{
  esp0xdeadbeef = {
    "site-b" = {
      pools = {
        p2p.ipv4 = "10.10.0.0/24";
        loopback.ipv4 = "10.19.0.0/24";
      };

      ownership.prefixes = [
        { kind = "tenant"; name = "client"; ipv4 = "10.20.20.0/24"; }
        { kind = "tenant"; name = "mgmt"; ipv4 = "10.20.30.0/24"; }
      ];

      communicationContract.relations = [
        {
          id = "deny-client-to-wan";
          priority = 100;
          from = { kind = "tenant"; name = "client"; };
          to = { kind = "external"; uplinks = [ "wan" ]; };
          trafficType = "any";
          action = "deny";
        }
        {
          id = "allow-mgmt-to-wan";
          priority = 200;
          from = { kind = "tenant"; name = "mgmt"; };
          to = { kind = "external"; uplinks = [ "wan" ]; };
          trafficType = "any";
          action = "allow";
        }
      ];

      topology.nodes = {
        access-client = {
          role = "access";
          attachments = [ { kind = "tenant"; name = "client"; } ];
        };
        access-mgmt = {
          role = "access";
          attachments = [ { kind = "tenant"; name = "mgmt"; } ];
        };
        downstream.role = "downstream-selector";
        policy.role = "policy";
        upstream.role = "upstream-selector";
        core-wan = {
          role = "core";
          uplinks.wan.ipv4 = [ "0.0.0.0/0" ];
        };
      };

      topology.links = [
        [ "access-client" "downstream" ]
        [ "access-mgmt" "downstream" ]
        [ "downstream" "policy" ]
        [ "policy" "upstream" ]
        [ "upstream" "core-wan" ]
      ];
    };
  };
}
NIX

nix run --no-warn-dirty --no-write-lock-file "path:${compiler_path}#compile" -- \
  "${negative_input}" >"${tmpdir}/compiler-negative.json"

nix run "${repo_root}#compile-and-build-forwarding-model" -- \
  "${negative_input}" >"${negative_json}"

# --- Negative assertions: topology exists but no allow relation → no lane-default routes ---
echo "=== Seeded negative: deny-only topology produces no selector lane-default routes ==="

jq -e '
  [
    .enterprise.esp0xdeadbeef.site."site-b".nodes
    | to_entries[]
    | .value.interfaces
    | to_entries[]
    | .value.routes.ipv4[]
    | select(.intent.kind == "default-reachability"
        and .lane != null
        and (.relationIds | type) == "array"
        and (.relationIds | contains(["deny-client-to-wan"])))
  ] | length == 0
' "${negative_json}" >/dev/null || {
  echo "FAIL seeded negative: deny relation leaked into lane-default route relationIds" >&2
  jq '[.enterprise.esp0xdeadbeef.site."site-b".nodes
    | to_entries[]
    | .key as $node
    | .value.interfaces
    | to_entries[]
    | .key as $iface
    | .value.routes.ipv4[]
    | select(.intent.kind == "default-reachability" and .lane != null)
    | { node: $node, iface: $iface, relationIds, direction, lane }]' "${negative_json}" >&2
  exit 1
}

# Additionally: mgmt tenant (with allow relation) SHOULD have lane-default routes
jq -e '
  [
    .enterprise.esp0xdeadbeef.site."site-b".nodes
    | to_entries[]
    | .value.interfaces
    | to_entries[]
    | .value.routes.ipv4[]
    | select(.intent.kind == "default-reachability"
        and .lane != null
        and (.relationIds | type) == "array"
        and (.relationIds | contains(["allow-mgmt-to-wan"])))
  ] | length > 0
' "${negative_json}" >/dev/null || {
  echo "FAIL: allowed tenant mgmt gets no lane-default routes with relationIds" >&2
  jq '[.enterprise.esp0xdeadbeef.site."site-b".nodes
    | to_entries[]
    | .key as $node
    | .value.interfaces
    | to_entries[]
    | .key as $iface
    | .value.routes.ipv4[]
    | select(.intent.kind == "default-reachability" and .lane != null)
    | { node: $node, iface: $iface, relationIds, direction, lane }]' "${negative_json}" >&2
  exit 1
}

echo "PASS: seeded negative — no selector lane-default routes with deny-only topology"

pass_timed "FS-180-FS-270-selector-relation-authority" "${start_ms}"
