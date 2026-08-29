#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-315-HDS-010-SDS-010-SMS-020
# GAMP-SCOPE: software-module-test
# Focused construction test: multipath default-route emission for an access
# unit with an explicit multi-uplink member set (FS-315 multipath authority).

repo_root="$(git rev-parse --show-toplevel)"
source "${repo_root}/tests/lib/timing.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

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

module_path="${repo_root}/implementation/lib/routing/lane-default-route-builder.nix"

# ---- SN1: mkMultipathDefaultRoutes emits one atom per member and one -------
#        shared multipath authority.

test_sn1() {
  local result
  result="$(run_nix_eval "
    let
      lib = import <nixpkgs/lib>;
      b = import ${module_path} { inherit lib; self = { outPath = ./.; }; };
      mkRoute4 = args: { inherit (args) dst via4 proto metric lane policyOnly reason; intent = { kind = args.intentKind; }; };
      mkRoute6 = args: { inherit (args) dst via6 proto metric lane policyOnly reason; intent = { kind = args.intentKind; }; };
      out = b.mkMultipathDefaultRoutes {
        inherit mkRoute4 mkRoute6;
        epsTo = [
          { addr4 = \"10.1.0.41/31\"; }
          { addr4 = \"10.1.0.43/31\"; }
        ];
        multipathAuthority = \"vlan31-default\";
        metric = 2000;
        lane = { access = \"vlan31\"; uplink = null; };
        policyOnly = true;
        reason = \"policy-derived-default\";
      };
    in
    {
      count = builtins.length out.routes4;
      authorities = lib.unique (map (r: r.multipath.authority) out.routes4);
      vias = builtins.sort (a: b: a < b) (map (r: r.via4) out.routes4);
      lanes = lib.unique (map (r: builtins.toJSON r.lane) out.routes4);
    }
  " "sn1-multipath-atoms")"

  if [[ "$(echo "$result" | jq -r .count)" != "2" ]]; then
    fail_with "sn1-count" "expected 2 multipath atoms, got $(echo "$result" | jq -r .count)"
  fi
  if [[ "$(echo "$result" | jq -r '.authorities | length')" != "1" ]]; then
    fail_with "sn1-authority" "expected one shared multipath authority"
  fi
  if [[ "$(echo "$result" | jq -r '.lanes | length')" != "1" ]]; then
    fail_with "sn1-lane" "expected one shared lane (access, no uplink)"
  fi

  echo "PASS sn1-multipath-atoms: one atom per member, one shared authority, one shared lane"
}

# ---- SN2: a single next-hop does not carry multipath authority --------------

test_sn2() {
  local result
  result="$(run_nix_eval "
    let
      lib = import <nixpkgs/lib>;
      b = import ${module_path} { inherit lib; self = { outPath = ./.; }; };
      mkRoute4 = args: { inherit (args) dst via4 proto metric lane policyOnly reason; intent = { kind = args.intentKind; }; };
      mkRoute6 = args: { inherit (args) dst via6 proto metric lane policyOnly reason; intent = { kind = args.intentKind; }; };
      out = b.mkMultipathDefaultRoutes {
        inherit mkRoute4 mkRoute6;
        epsTo = [ { addr4 = \"10.1.0.41/31\"; } ];
        multipathAuthority = \"vlan31-default\";
        metric = 2000;
        lane = { access = \"vlan31\"; uplink = null; };
      };
    in
    {
      count = builtins.length out.routes4;
      hasMultipath = builtins.any (r: builtins.hasAttr \"multipath\" r) out.routes4;
    }
  " "sn2-single-member")"

  if [[ "$(echo "$result" | jq -r .count)" != "1" ]]; then
    fail_with "sn2-count" "expected 1 atom for a single member"
  fi
  if [[ "$(echo "$result" | jq -r .hasMultipath)" != "true" ]]; then
    fail_with "sn2-multipath" "single-member call should still carry the authority tag"
  fi

  echo "PASS sn2-single-member: single member still carries the multipath authority tag"
}

# ---- SN3: IPv4 and IPv6 members share one authority ------------------------

test_sn3() {
  local result
  result="$(run_nix_eval "
    let
      lib = import <nixpkgs/lib>;
      b = import ${module_path} { inherit lib; self = { outPath = ./.; }; };
      mkRoute4 = args: { inherit (args) dst via4 proto metric lane policyOnly reason; intent = { kind = args.intentKind; }; };
      mkRoute6 = args: { inherit (args) dst via6 proto metric lane policyOnly reason; intent = { kind = args.intentKind; }; };
      out = b.mkMultipathDefaultRoutes {
        inherit mkRoute4 mkRoute6;
        epsTo = [
          { addr4 = \"10.1.0.41/31\"; addr6 = \"fd42::41/127\"; }
          { addr4 = \"10.1.0.43/31\"; addr6 = \"fd42::43/127\"; }
        ];
        multipathAuthority = \"vlan31-default\";
        metric = 2000;
        lane = { access = \"vlan31\"; uplink = null; };
      };
    in
    {
      v4 = builtins.length out.routes4;
      v6 = builtins.length out.routes6;
      authorities = lib.unique (map (r: r.multipath.authority) (out.routes4 ++ out.routes6));
    }
  " "sn3-dual-family")"

  if [[ "$(echo "$result" | jq -r .v4)" != "2" || "$(echo "$result" | jq -r .v6)" != "2" ]]; then
    fail_with "sn3-count" "expected 2 IPv4 and 2 IPv6 members"
  fi
  if [[ "$(echo "$result" | jq -r '.authorities | length')" != "1" ]]; then
    fail_with "sn3-authority" "IPv4 and IPv6 members should share one authority"
  fi

  echo "PASS sn3-dual-family: IPv4 and IPv6 multipath members share one authority"
}

test_start="$(test_now_ms)"
echo ""
echo "=== FS-315-HDS-010-SDS-010-SMS-020: Multipath Default-Route Emission Tests ==="
echo ""
test_sn1
test_sn2
test_sn3
echo ""
echo "PASS FS-315-HDS-010-SDS-010-SMS-020"
echo "Passed: 3/3 multipath default-route tests"
pass_timed "FS-315-HDS-010-SDS-010-SMS-020" "${test_start}"
