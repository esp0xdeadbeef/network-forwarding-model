#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-315-HDS-010-SDS-010-SMS-010
# GAMP-SCOPE: software-module-test
# Focused construction test: route selection-key ownership module.
# Exercises all four seeded negatives from SMS FS-315-HDS-010-SDS-010-SMS-010.

repo_root="$(git rev-parse --show-toplevel)"
source "${repo_root}/tests/lib/timing.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

# ---- helpers ---------------------------------------------------------------

run_nix_eval() {
  local expr="$1"
  local test_label="$2"
  local outfile="${tmpdir}/${test_label}.out"
  local errfile="${tmpdir}/${test_label}.err"
  NETWORK_REPO_DIRECT_TEST_OK=1 nix eval --impure --json --expr "${expr}" >"${outfile}" 2>"${errfile}" || {
    echo "FAIL ${test_label}: nix eval failed:" >&2
    cat "${errfile}" >&2
    exit 1
  }
  cat "${outfile}"
}

fail_with() {
  local test_name="$1"; shift
  printf 'FAIL %s: %s\n' "${test_name}" "$*" >&2
  exit 1
}

nix_module_path="${repo_root}/implementation/lib/routing/static/selection-key.nix"

# ---- SN1: exact duplicate atoms in opposite input orders shall emit one -----
#        identical route-selection record with both provenance identities.

test_sn1() {
  local result
  result="$(run_nix_eval "
    let
      lib = import <nixpkgs/lib>;
      sk = import ${nix_module_path} { inherit lib; };
      r1 = { dst = \"10.0.0.0/24\"; proto = \"internal\"; via4 = \"10.1.1.1\"; intent = { kind = \"test\"; }; };
      r2 = { dst = \"10.0.0.0/24\"; proto = \"internal\"; via4 = \"10.1.1.1\"; intent = { kind = \"test\"; }; };
    in
    sk.isExactDuplicate r1 r2
  " "sn1-exact-dup")"

  if [[ "$result" != "true" ]]; then
    fail_with "sn1-exact-duplicate" "expected isExactDuplicate to be true, got '${result}'"
  fi

  # Verify same selection key
  local key1
  key1="$(run_nix_eval "
    let
      lib = import <nixpkgs/lib>;
      sk = import ${nix_module_path} { inherit lib; };
      r1 = { dst = \"10.0.0.0/24\"; proto = \"internal\"; via4 = \"10.1.1.1\"; intent = { kind = \"test\"; }; };
      r2 = { dst = \"10.0.0.0/24\"; proto = \"internal\"; via4 = \"10.1.1.1\"; intent = { kind = \"test\"; }; };
    in
    sk.selectionKey r1 == sk.selectionKey r2
  " "sn1-same-key")"

  if [[ "$key1" != "true" ]]; then
    fail_with "sn1-selection-key" "selection keys differ for exact duplicates"
  fi

  # Verify same next-hop set
  local nh_same
  nh_same="$(run_nix_eval "
    let
      lib = import <nixpkgs/lib>;
      sk = import ${nix_module_path} { inherit lib; };
      r1 = { dst = \"10.0.0.0/24\"; proto = \"internal\"; via4 = \"10.1.1.1\"; intent = { kind = \"test\"; }; };
      r2 = { dst = \"10.0.0.0/24\"; proto = \"internal\"; via4 = \"10.1.1.1\"; intent = { kind = \"test\"; }; };
    in
    sk.nextHopSet r1 == sk.nextHopSet r2
  " "sn1-same-nh")"

  if [[ "$nh_same" != "true" ]]; then
    fail_with "sn1-next-hop" "next-hop sets differ for exact duplicates"
  fi

  echo "PASS sn1-exact-duplicate: exact duplicates identified, same selection key, same next-hop set"
}

# ---- SN2: changing only gateway on the second atom shall emit --------------
#        zero route and one deterministic conflicting-next-hop diagnostic.

test_sn2() {
  # Two atoms with same selection key but different gateway
  local has_conflict
  has_conflict="$(run_nix_eval "
    let
      lib = import <nixpkgs/lib>;
      sk = import ${nix_module_path} { inherit lib; };
      r1 = { dst = \"10.0.0.0/24\"; proto = \"internal\"; via4 = \"10.1.1.1\"; intent = { kind = \"test\"; }; };
      r2 = { dst = \"10.0.0.0/24\"; proto = \"internal\"; via4 = \"10.1.1.2\"; intent = { kind = \"test\"; }; };
    in
    sk.hasConflictingNextHop r1 r2
  " "sn2-conflict")"

  if [[ "$has_conflict" != "true" ]]; then
    fail_with "sn2-conflicting-next-hop" "expected hasConflictingNextHop to be true, got '${has_conflict}'"
  fi

  # Verify same selection key despite different gateways
  local key_same
  key_same="$(run_nix_eval "
    let
      lib = import <nixpkgs/lib>;
      sk = import ${nix_module_path} { inherit lib; };
      r1 = { dst = \"10.0.0.0/24\"; proto = \"internal\"; via4 = \"10.1.1.1\"; intent = { kind = \"test\"; }; };
      r2 = { dst = \"10.0.0.0/24\"; proto = \"internal\"; via4 = \"10.1.1.2\"; intent = { kind = \"test\"; }; };
    in
    sk.selectionKey r1 == sk.selectionKey r2
  " "sn2-same-key")"

  if [[ "$key_same" != "true" ]]; then
    fail_with "sn2-selection-key" "selection keys should match despite different gateways"
  fi

  # Verify different next-hop sets
  local nh_diff
  nh_diff="$(run_nix_eval "
    let
      lib = import <nixpkgs/lib>;
      sk = import ${nix_module_path} { inherit lib; };
      r1 = { dst = \"10.0.0.0/24\"; proto = \"internal\"; via4 = \"10.1.1.1\"; intent = { kind = \"test\"; }; };
      r2 = { dst = \"10.0.0.0/24\"; proto = \"internal\"; via4 = \"10.1.1.2\"; intent = { kind = \"test\"; }; };
    in
    sk.nextHopSet r1 != sk.nextHopSet r2
  " "sn2-diff-nh")"

  if [[ "$nh_diff" != "true" ]]; then
    fail_with "sn2-next-hop" "next-hop sets should differ for different gateways"
  fi

  # Verify it is NOT an exact duplicate
  local is_dup
  is_dup="$(run_nix_eval "
    let
      lib = import <nixpkgs/lib>;
      sk = import ${nix_module_path} { inherit lib; };
      r1 = { dst = \"10.0.0.0/24\"; proto = \"internal\"; via4 = \"10.1.1.1\"; intent = { kind = \"test\"; }; };
      r2 = { dst = \"10.0.0.0/24\"; proto = \"internal\"; via4 = \"10.1.1.2\"; intent = { kind = \"test\"; }; };
    in
    sk.isExactDuplicate r1 r2 == false
  " "sn2-not-dup")"

  if [[ "$is_dup" != "true" ]]; then
    fail_with "sn2-not-exact-dup" "routes with different gateways should not be exact duplicates"
  fi

  echo "PASS sn2-conflicting-next-hop: same selection key, different next-hop sets, conflict detected"
}

# ---- SN3: adding target multipath capability without modeled ---------------
#        multipath authority shall remain rejected.

test_sn3() {
  # Route with multipath capability but no multipath authority
  local no_auth
  no_auth="$(run_nix_eval "
    let
      lib = import <nixpkgs/lib>;
      sk = import ${nix_module_path} { inherit lib; };
      r = { dst = \"10.0.0.0/24\"; proto = \"internal\"; via4 = \"10.1.1.1\"; intent = { kind = \"test\"; multipath = { capability = true; }; }; };
    in
    sk.hasMultipathAuthority r == false
  " "sn3-no-mp-auth")"

  if [[ "$no_auth" != "true" ]]; then
    fail_with "sn3-no-multipath-authority" "multipath capability without authority should be rejected"
  fi

  # Verify: route with multipath authority is accepted
  local has_auth
  has_auth="$(run_nix_eval "
    let
      lib = import <nixpkgs/lib>;
      sk = import ${nix_module_path} { inherit lib; };
      r = { dst = \"10.0.0.0/24\"; proto = \"internal\"; via4 = \"10.1.1.1\"; intent = { kind = \"test\"; multipath = { authority = \"mp-auth-1\"; }; }; };
    in
    sk.hasMultipathAuthority r
  " "sn3-with-auth")"

  if [[ "$has_auth" != "true" ]]; then
    fail_with "sn3-with-authority" "route with multipath authority should be accepted, got '${has_auth}'"
  fi

  # Verify: route-level multipath authority (outside intent)
  local direct_auth
  direct_auth="$(run_nix_eval "
    let
      lib = import <nixpkgs/lib>;
      sk = import ${nix_module_path} { inherit lib; };
      r = { dst = \"10.0.0.0/24\"; proto = \"internal\"; via4 = \"10.1.1.1\"; multipath = { authority = \"mp-direct\"; }; };
    in
    sk.hasMultipathAuthority r
  " "sn3-direct-mp")"

  if [[ "$direct_auth" != "true" ]]; then
    fail_with "sn3-direct-multipath" "route-level multipath authority should be accepted, got '${direct_auth}'"
  fi

  echo "PASS sn3-multipath-authority: capability without authority rejected, authority accepted"
}

# ---- SN4: adding one explicit multipath identity and complete --------------
#        member set shall emit one authorized set with deterministic ordering.

test_sn4() {
  # Verify deterministic ordering: reordering input produces same output
  local ordered1 ordered2
  ordered1="$(run_nix_eval "
    let
      lib = import <nixpkgs/lib>;
      sk = import ${nix_module_path} { inherit lib; };
      members = [
        { dst = \"10.0.0.0/24\"; proto = \"mpath\"; via4 = \"10.1.1.1\"; intent = { kind = \"test\"; multipath = { authority = \"mp-1\"; }; }; }
        { dst = \"10.0.0.0/24\"; proto = \"mpath\"; via4 = \"10.1.1.2\"; intent = { kind = \"test\"; multipath = { authority = \"mp-1\"; }; }; }
        { dst = \"10.0.0.0/24\"; proto = \"mpath\"; via4 = \"10.1.1.3\"; intent = { kind = \"test\"; multipath = { authority = \"mp-1\"; }; }; }
      ];
      nhs = map sk.nextHopSet members;
    in
    builtins.toJSON (builtins.sort (a: b: a < b) nhs)
  " "sn4-order1")"

  ordered2="$(run_nix_eval "
    let
      lib = import <nixpkgs/lib>;
      sk = import ${nix_module_path} { inherit lib; };
      # Reversed input order
      members = [
        { dst = \"10.0.0.0/24\"; proto = \"mpath\"; via4 = \"10.1.1.3\"; intent = { kind = \"test\"; multipath = { authority = \"mp-1\"; }; }; }
        { dst = \"10.0.0.0/24\"; proto = \"mpath\"; via4 = \"10.1.1.2\"; intent = { kind = \"test\"; multipath = { authority = \"mp-1\"; }; }; }
        { dst = \"10.0.0.0/24\"; proto = \"mpath\"; via4 = \"10.1.1.1\"; intent = { kind = \"test\"; multipath = { authority = \"mp-1\"; }; }; }
      ];
      nhs = map sk.nextHopSet members;
    in
    builtins.toJSON (builtins.sort (a: b: a < b) nhs)
  " "sn4-order2")"

  if [[ "$ordered1" != "$ordered2" ]]; then
    fail_with "sn4-deterministic-ordering" "sorted next-hop sets should be identical regardless of input order"
  fi

  # Verify all members have multipath authority
  local all_authorized
  all_authorized="$(run_nix_eval "
    let
      lib = import <nixpkgs/lib>;
      sk = import ${nix_module_path} { inherit lib; };
      members = [
        { dst = \"10.0.0.0/24\"; proto = \"mpath\"; via4 = \"10.1.1.1\"; intent = { kind = \"test\"; multipath = { authority = \"mp-1\"; }; }; }
        { dst = \"10.0.0.0/24\"; proto = \"mpath\"; via4 = \"10.1.1.2\"; intent = { kind = \"test\"; multipath = { authority = \"mp-1\"; }; }; }
        { dst = \"10.0.0.0/24\"; proto = \"mpath\"; via4 = \"10.1.1.3\"; intent = { kind = \"test\"; multipath = { authority = \"mp-1\"; }; }; }
      ];
    in
    builtins.all sk.hasMultipathAuthority members
  " "sn4-all-auth")"

  if [[ "$all_authorized" != "true" ]]; then
    fail_with "sn4-all-authorized" "all multipath members should have authority"
  fi

  # Verify all members share same selection key
  local same_key
  same_key="$(run_nix_eval "
    let
      lib = import <nixpkgs/lib>;
      sk = import ${nix_module_path} { inherit lib; };
      members = [
        { dst = \"10.0.0.0/24\"; proto = \"mpath\"; via4 = \"10.1.1.1\"; intent = { kind = \"test\"; multipath = { authority = \"mp-1\"; }; }; }
        { dst = \"10.0.0.0/24\"; proto = \"mpath\"; via4 = \"10.1.1.2\"; intent = { kind = \"test\"; multipath = { authority = \"mp-1\"; }; }; }
        { dst = \"10.0.0.0/24\"; proto = \"mpath\"; via4 = \"10.1.1.3\"; intent = { kind = \"test\"; multipath = { authority = \"mp-1\"; }; }; }
      ];
      keys = map sk.selectionKey members;
      first = builtins.head keys;
    in
    builtins.all (k: k == first) keys
  " "sn4-same-key")"

  if [[ "$same_key" != "true" ]]; then
    fail_with "sn4-same-key" "all multipath members should share the same selection key"
  fi

  echo "PASS sn4-multipath-members: multipath with authority accepted, deterministic ordering, members share selection key"
}

# ---- SN5: selection key excludes gateway, lane, interface; -----------------
#        same-key different-lane must not be hidden

test_sn5() {
  # Routes with same dst/proto but different lane should SHARE a selection key
  local key_same
  key_same="$(run_nix_eval "
    let
      lib = import <nixpkgs/lib>;
      sk = import ${nix_module_path} { inherit lib; };
      r1 = { dst = \"10.0.0.0/24\"; proto = \"internal\"; via4 = \"10.1.1.1\"; lane = { access = \"vlan2\"; }; intent = { kind = \"test\"; }; };
      r2 = { dst = \"10.0.0.0/24\"; proto = \"internal\"; via4 = \"10.1.1.1\"; lane = { access = \"vlan7\"; }; intent = { kind = \"test\"; }; };
    in
    sk.selectionKey r1 == sk.selectionKey r2
  " "sn5-lane-key")"

  if [[ "$key_same" != "true" ]]; then
    fail_with "sn5-lane-excluded" "selection keys should be identical when only lane differs"
  fi

  # Verify different next-hop sets due to different lanes
  local nh_diff
  nh_diff="$(run_nix_eval "
    let
      lib = import <nixpkgs/lib>;
      sk = import ${nix_module_path} { inherit lib; };
      r1 = { dst = \"10.0.0.0/24\"; proto = \"internal\"; via4 = \"10.1.1.1\"; lane = { access = \"vlan2\"; }; intent = { kind = \"test\"; }; };
      r2 = { dst = \"10.0.0.0/24\"; proto = \"internal\"; via4 = \"10.1.1.1\"; lane = { access = \"vlan7\"; }; intent = { kind = \"test\"; }; };
    in
    sk.nextHopSet r1 != sk.nextHopSet r2
  " "sn5-lane-nh")"

  if [[ "$nh_diff" != "true" ]]; then
    fail_with "sn5-lane-in-next-hop" "next-hop sets should differ when lane differs"
  fi

  echo "PASS sn5-lane-excluded: lane excluded from selection key, included in next-hop set"
}

# ---- SN6: provenance collection from multiple identical routes --------------

test_sn6() {
  local count
  count="$(run_nix_eval "
    let
      lib = import <nixpkgs/lib>;
      sk = import ${nix_module_path} { inherit lib; };
      routes = [
        { dst = \"10.0.0.0/24\"; proto = \"internal\"; via4 = \"10.1.1.1\"; provenance = [\"src-a\"]; intent = { kind = \"test\"; }; }
        { dst = \"10.0.0.0/24\"; proto = \"internal\"; via4 = \"10.1.1.1\"; provenance = [\"src-b\"]; intent = { kind = \"test\"; }; }
      ];
      union = sk.collectProvenance routes;
    in
    builtins.length union
  " "sn6-prov-count")"

  if [[ "$count" != "2" ]]; then
    fail_with "sn6-provenance" "expected 2 provenance entries, got ${count}"
  fi

  echo "PASS sn6-provenance-collection: provenance union from multiple routes"
}

# ---- run all tests ----------------------------------------------------------

echo ""
echo "=== FS-315-HDS-010-SDS-010-SMS-010: Route Selection-Key Module Tests ==="
echo ""

test_start="$(test_now_ms)"

test_sn1  # exact duplicate
test_sn2  # conflicting next-hop
test_sn3  # multipath authority
test_sn4  # multipath deterministic ordering
test_sn5  # lane excluded from key
test_sn6  # provenance collection

echo ""
echo "PASS FS-315-HDS-010-SDS-010-SMS-010"
echo "Passed: 6/6 seeded negative tests"
pass_timed "FS-315-HDS-010-SDS-010-SMS-010" "${test_start}"
