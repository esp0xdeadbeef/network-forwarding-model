#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-300-HDS-010-SDS-010-SMS-010
# GAMP-SCOPE: software-module-test
# Source-scope validation: SN1 (non-existent site scope), SN2 (ambiguous tenant)

repo_root="$(git rev-parse --show-toplevel)"
source "${repo_root}/tests/lib/timing.sh"

base_intent="${repo_root}/tests/fixtures/examples/s-router-overlay-dns-lane-policy/intent.nix"
tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

# ---- helpers ---------------------------------------------------------------

fail_with() {
  local test_name="$1"; shift
  printf 'FAIL %s: %s\n' "${test_name}" "$*" >&2
  exit 1
}

compile_intent() {
  local intent_file="$1"
  local output_file="$2"
  local errfile="${tmpdir}/compile-err.txt"
  NETWORK_REPO_DIRECT_TEST_OK=1 \
    nix run "${repo_root}#compile-and-build-forwarding-model" -- "$intent_file" \
    >"$output_file" 2>"$errfile" || true
  cat "$errfile" >&2
}

compile_and_expect_error() {
  local intent_file="$1"
  local expected_code="$2"
  local test_label="$3"
  local errfile="${tmpdir}/compile-err.txt"
  local outfile="${tmpdir}/compile-out.json"

  if NETWORK_REPO_DIRECT_TEST_OK=1 \
    nix run "${repo_root}#compile-and-build-forwarding-model" -- "$intent_file" \
    >"$outfile" 2>"$errfile"; then
    fail_with "${test_label}" "expected rejection but compilation succeeded"
  fi

  local err_text
  err_text="$(cat "$errfile")"
  if ! echo "$err_text" | grep -q "\"code\":\"${expected_code}\""; then
    printf 'STDERR:\n%s\n' "$err_text" >&2
    fail_with "${test_label}" "expected diagnostic ${expected_code} not found in error output"
  fi
}

compile_and_expect_success() {
  local intent_file="$1"
  local test_label="$2"
  local outfile="${tmpdir}/compile-out.json"
  local errfile="${tmpdir}/compile-err.txt"

  if ! NETWORK_REPO_DIRECT_TEST_OK=1 \
    nix run "${repo_root}#compile-and-build-forwarding-model" -- "$intent_file" \
    >"$outfile" 2>"$errfile"; then
    printf 'STDERR:\n' >&2
    cat "$errfile" >&2
    fail_with "${test_label}" "compilation failed unexpectedly"
  fi
  printf '%s' "$outfile"
}

# ---- SN1: non-existent tenant in underlayAccess ---------------------------

sn1_intent="${tmpdir}/sn1-intent.nix"
cp "$base_intent" "$sn1_intent"

# Replace underlayAccess client -> NONEXISTENT (only for site-a)
sed -i 's/underlayAccess = { kind = "tenant"; name = "client"; };/underlayAccess = { kind = "tenant"; name = "NONEXISTENT"; };/' "$sn1_intent"

start_ms="$(test_now_ms)"
compile_and_expect_error "$sn1_intent" "E_OVERLAY_ACCESS_ATTACHMENT_REQUIRED" \
  "fs300-source-scope-sn1-nonexistent-tenant"
pass_timed "fs300-source-scope-sn1-nonexistent-tenant" "$start_ms"

# ---- SN1 recovery: fix the tenant -----------------------------------------

sn1_recovery="${tmpdir}/sn1-recovery.nix"
cp "$base_intent" "$sn1_recovery"
# Intent is already valid - compile and verify overlay routes have lane metadata

start_ms="$(test_now_ms)"
outfile="$(compile_and_expect_success "$sn1_recovery" "fs300-source-scope-sn1-recovery")"
pass_timed "fs300-source-scope-sn1-recovery:compile" "$start_ms"

# Verify source-scoped overlay routes carry lane metadata (like SMS-020 does)
jq -e '
  .enterprise.esp0xdeadbeef.site["site-a"] as $site
  | def source_scoped_overlay_routes($node):
      $site.nodes[$node].interfaces
      | to_entries[]
      | (.value.routes.ipv4[]?, .value.routes.ipv6[]?)
      | select(
          (.proto // null) == "internal"
          and (.intent.kind // null) == "overlay-reachability"
          and (.overlay // null) == "east-west"
        );
    def has_lane_metadata($node):
      [source_scoped_overlay_routes($node)
        | select((.lane.access // null) != null and (.lane.uplink // null) != null)]
      | length;
    has_lane_metadata("s-router-downstream-selector") > 0
    and has_lane_metadata("s-router-policy-only") > 0
' "$outfile" >/dev/null || {
  echo "FAIL fs300-source-scope-sn1-recovery: recovered fixture must produce source-scoped overlay routes with lane.access and lane.uplink metadata" >&2
  exit 1
}
pass_timed "fs300-source-scope-sn1-recovery:validate" "$start_ms"

# ---- SN2: same-named tenant in two sites — site context disambiguates ------

# The base fixture already has tenant "client" in site-a and "client" in site-c.
# UnderlayAccess is scoped per-site — each site's overlay resolves its own
# "client" tenant locally. This test asserts that both sites produce valid
# source-scoped routes without ambiguity errors.

start_ms="$(test_now_ms)"
outfile="$(compile_and_expect_success "$base_intent" "fs300-source-scope-sn2-no-ambiguity")"
pass_timed "fs300-source-scope-sn2-no-ambiguity:compile" "$start_ms"

jq -e '
  def source_scoped_overlay_routes($site):
    $site.nodes
    | to_entries[]
    | .value.interfaces
    | to_entries[]
    | (.value.routes.ipv4[]?, .value.routes.ipv6[]?)
    | select(
        (.proto // null) == "internal"
        and (.intent.kind // null) == "overlay-reachability"
        and (.overlay // null) == "east-west"
      );
  def has_lane_metadata($site):
    [source_scoped_overlay_routes($site)
      | select((.lane.access // null) != null and (.lane.uplink // null) != null)]
    | length;
  has_lane_metadata(.enterprise.esp0xdeadbeef.site["site-a"]) > 0
  and has_lane_metadata(.enterprise.esp0xdeadbeef.site["site-c"]) > 0
' "$outfile" >/dev/null || {
  echo "FAIL fs300-source-scope-sn2-no-ambiguity: both sites must produce source-scoped overlay routes with lane metadata; site context must disambiguate tenant 'client'" >&2
  exit 1
 }
pass_timed "fs300-source-scope-sn2-no-ambiguity:validate" "$start_ms"

echo "PASS FS-300-HDS-010-SDS-010-SMS-010"
