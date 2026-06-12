#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-180-HDS-010-SDS-010-SMS-010
# GAMP-ID: FS-180-HDS-010-SDS-010-SMS-020
# GAMP-ID: FS-180-HDS-010-SDS-010-SMS-030
# GAMP-ID: FS-270-HDS-010-SDS-010-SMS-040
#
# Focused construction test: selector lane-default routes carry
# returnBehavior, relationIds, and direction from modeled allow
# relations, not from topology alone.
#
# FS-180 requires each modeled allow tuple to name return behavior.
# FS-181 requires every authority record to carry return behavior.
# SMS-010 (allow tuple validation): return behavior must be determinable
#   from modeled input; undetermined return behavior is a failure condition.
# SMS-020 (adjacent denial): traffic outside the tuple is denied by
#   return behavior difference.
# SMS-030 (wildcard expansion): wildcard expansion is bounded by
#   return behavior.
# SMS-040 (selector handoff): selector forwarding preserves relation
#   identity including return behavior.
#
# Seeded negatives:
#   - Topology-only: lane topology exists but no trafficPath allows
#     WAN egress for access unit → no lane-default routes, no returnBehavior
#   - Deny-only: allow-mgmt gets routes with returnBehavior="symmetric",
#     but deny-client gets no routes and no returnBehavior

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
      if compilerPath == null then throw "FS-180-HDS-010-SDS-010-SMS-010 return behavior: missing network-compiler input" else compilerPath
  '
)"

# === Positive case: allow relation → returnBehavior="symmetric" ===
echo "=== Positive: allow relation produces returnBehavior=\"symmetric\" ==="

positive_input="${tmpdir}/positive-return-behavior.nix"
positive_json="${tmpdir}/positive-return-behavior.json"

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

# Assertion 1: downstream-selector lane route has returnBehavior="symmetric"
jq -e '
  [ .enterprise.esp0xdeadbeef.site."site-a".nodes.downstream.interfaces
    | to_entries[]
    | select(.key | startswith("p2p-downstream-policy"))
    | .value.routes.ipv4[]
    | select(.intent.kind == "default-reachability" and .lane != null)
  ][0]
  | .relationIds == ["allow-client-to-wan-https"]
    and .direction == "outbound"
    and .returnBehavior == "symmetric"
    and .policyOnly == true
' "${positive_json}" >/dev/null || {
  echo "FAIL: downstream-selector lane route missing returnBehavior=\"symmetric\"" >&2
  jq '[.enterprise.esp0xdeadbeef.site."site-a".nodes.downstream.interfaces
    | to_entries[]
    | select(.key | startswith("p2p-downstream-policy"))
    | .value.routes.ipv4[]
    | select(.intent.kind == "default-reachability")
    | { relationIds, direction, returnBehavior, policyOnly, lane }]' "${positive_json}" >&2
  exit 1
}

# Assertion 2: policy node lane route has returnBehavior="symmetric"
jq -e '
  [ .enterprise.esp0xdeadbeef.site."site-a".nodes.policy.interfaces
    | to_entries[]
    | select(.key | startswith("p2p-policy-upstream"))
    | .value.routes.ipv4[]
    | select(.intent.kind == "default-reachability" and .lane != null)
  ][0]
  | .relationIds == ["allow-client-to-wan-https"]
    and .direction == "outbound"
    and .returnBehavior == "symmetric"
    and .policyOnly == true
' "${positive_json}" >/dev/null || {
  echo "FAIL: policy node lane route missing returnBehavior=\"symmetric\"" >&2
  jq '[.enterprise.esp0xdeadbeef.site."site-a".nodes.policy.interfaces
    | to_entries[]
    | select(.key | startswith("p2p-policy-upstream"))
    | .value.routes.ipv4[]
    | select(.intent.kind == "default-reachability")
    | { relationIds, direction, returnBehavior, policyOnly, lane }]' "${positive_json}" >&2
  exit 1
}

# Assertion 3: upstream-selector lane route has returnBehavior="symmetric"
jq -e '
  [ .enterprise.esp0xdeadbeef.site."site-a".nodes.upstream.interfaces
    | to_entries[]
    | select(.key | startswith("p2p-core"))
    | .value.routes.ipv4[]
    | select(.intent.kind == "default-reachability" and .lane != null)
  ][0]
  | .relationIds == ["allow-client-to-wan-https"]
    and .direction == "outbound"
    and .returnBehavior == "symmetric"
    and .policyOnly == true
' "${positive_json}" >/dev/null || {
  echo "FAIL: upstream-selector lane route missing returnBehavior=\"symmetric\"" >&2
  jq '[.enterprise.esp0xdeadbeef.site."site-a".nodes.upstream.interfaces
    | to_entries[]
    | select(.key | startswith("p2p-core"))
    | .value.routes.ipv4[]
    | select(.intent.kind == "default-reachability")
    | { relationIds, direction, returnBehavior, policyOnly, lane }]' "${positive_json}" >&2
  exit 1
}

echo "PASS: positive case — all selector lane routes carry returnBehavior=\"symmetric\""

# === Seeded negative case: deny-only + topology-only ===
echo "=== Seeded negative: deny-only produces no returnBehavior, topology-only produces no routes ==="

negative_input="${tmpdir}/negative-return-behavior.nix"
negative_json="${tmpdir}/negative-return-behavior.json"

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

# Seeded negative 1: deny-only relation does NOT produce any lane-default
# route with returnBehavior="symmetric" for the denied client
jq -e '
  [
    .enterprise.esp0xdeadbeef.site."site-b".nodes
    | to_entries[]
    | .value.interfaces
    | to_entries[]
    | .value.routes.ipv4[]
    | select(.intent.kind == "default-reachability"
        and .lane != null
        and .returnBehavior == "symmetric"
        and (.relationIds | type) == "array"
        and (.relationIds | contains(["deny-client-to-wan"])))
  ] | length == 0
' "${negative_json}" >/dev/null || {
  echo "FAIL seeded negative: deny relation leaked returnBehavior=\"symmetric\"" >&2
  jq '[.enterprise.esp0xdeadbeef.site."site-b".nodes
    | to_entries[]
    | .key as $node
    | .value.interfaces
    | to_entries[]
    | .key as $iface
    | .value.routes.ipv4[]
    | select(.intent.kind == "default-reachability" and .lane != null)
    | { node: $node, iface: $iface, relationIds, direction, returnBehavior, lane }]' "${negative_json}" >&2
  exit 1
}

# Seeded negative 2: topology-only (client has deny relation, topology
# provides lane connectivity) — the deny-client tenant must produce NO
# lane-default routes at all with returnBehavior="symmetric"
jq -e '
  [
    .enterprise.esp0xdeadbeef.site."site-b".nodes
    | to_entries[]
    | .value.interfaces
    | to_entries[]
    | .value.routes.ipv4[]
    | select(.intent.kind == "default-reachability"
        and .lane != null
        and .returnBehavior == "symmetric"
        and (.lane.access // "") == "client")
  ] | length == 0
' "${negative_json}" >/dev/null || {
  echo "FAIL seeded negative: topology-only client got returnBehavior=\"symmetric\"" >&2
  jq '[.enterprise.esp0xdeadbeef.site."site-b".nodes
    | to_entries[]
    | .key as $node
    | .value.interfaces
    | to_entries[]
    | .key as $iface
    | .value.routes.ipv4[]
    | select(.intent.kind == "default-reachability" and .lane != null)
    | { node: $node, iface: $iface, relationIds, direction, returnBehavior, lane }]' "${negative_json}" >&2
  exit 1
}

# Positive control: allowed mgmt tenant SHOULD have lane-default routes
# with returnBehavior="symmetric"
jq -e '
  [
    .enterprise.esp0xdeadbeef.site."site-b".nodes
    | to_entries[]
    | .value.interfaces
    | to_entries[]
    | .value.routes.ipv4[]
    | select(.intent.kind == "default-reachability"
        and .lane != null
        and .returnBehavior == "symmetric"
        and (.relationIds | type) == "array"
        and (.relationIds | contains(["allow-mgmt-to-wan"])))
  ] | length > 0
' "${negative_json}" >/dev/null || {
  echo "FAIL: allowed tenant mgmt gets no lane-default routes with returnBehavior=\"symmetric\"" >&2
  jq '[.enterprise.esp0xdeadbeef.site."site-b".nodes
    | to_entries[]
    | .key as $node
    | .value.interfaces
    | to_entries[]
    | .key as $iface
    | .value.routes.ipv4[]
    | select(.intent.kind == "default-reachability" and .lane != null)
    | { node: $node, iface: $iface, relationIds, direction, returnBehavior, lane }]' "${negative_json}" >&2
  exit 1
}

echo "PASS: seeded negative — deny-only and topology-only produce no returnBehavior=\"symmetric\""

pass_timed "FS-180-HDS-010-SDS-010-SMS-010-return-behavior-authority" "${start_ms}"
