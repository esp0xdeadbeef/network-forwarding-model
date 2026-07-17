#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-640-HDS-010-SDS-010-SMS-060
# Construction test: NFM returnBehavior normalization scoping
# Trace chain: URS → FS-640 → FS-640-HDS-010 → FS-640-HDS-010-SDS-010 → SMS-060
#
# Verifies normalizeCommunicationContract in compiler-input/sites/shape.nix
# preserves explicit return authority, rejects incomplete allow relations,
# and removes blanket symmetric injection based on endpoint kinds, traffic
# type, or bidirectional flag per FS-180/FS-620/FS-640.
#
# Seeded negatives per SMS-060:
#   N1: missing tenant-to-WAN return behavior → REJECT (not inject symmetric)
#   N2: explicit returnBehavior preserved verbatim (one-way and symmetric)
#   N3: nested stateful-return preserved, not overwritten by injection
#   N4: bidirectional=true without return field → REJECT (not infer symmetric)

repo_root="$(git rev-parse --show-toplevel)"
source "${repo_root}/tests/lib/timing.sh"

start_ms="$(test_now_ms)"
export NFM_REPO_ROOT="${repo_root}"

fail_test() {
  printf 'FAIL FS-640-SMS-060 returnBehavior scoping: %s\n' "$*" >&2
  exit 1
}

# ── Common nix-eval helper ──
# Evaluates normalizeCommunicationContract on a JSON fixture.
# The fixture JSON must have a "communicationContract" key with "allowedRelations".
# Returns JSON array of the output allowedRelations.
# If the function throws, the nix eval fails and the error message is captured.
eval_fixture() {
  local fixture_json="$1"   # JSON string of the site fixture
  local fixture_file="$2"   # temp file to write it to
  printf '%s' "$fixture_json" > "$fixture_file"
  nix eval --impure --json --expr '
    let
      repoRoot = builtins.getEnv "NFM_REPO_ROOT";
      flake = builtins.getFlake ("path:" + repoRoot);
      pkgs = flake.inputs.nixpkgs.legacyPackages.${builtins.currentSystem};
      lib = pkgs.lib;
      attrs = import (repoRoot + "/compiler-input/sites/attrs.nix") { inherit lib; };
      shape = import (repoRoot + "/compiler-input/sites/shape.nix") {
        inherit (attrs) getAttrPathOr hasAttrPath;
      };
      fixtureFile = builtins.getEnv "NFM_FIXTURE_FILE";
      fixture = builtins.fromJSON (builtins.readFile fixtureFile);
      result = shape.normalizeCommunicationContract fixture;
    in
      result.allowedRelations or []
  '
}

# ── Assertion helpers ──

assert_returnBehavior_equals() {
  local label="$1" relations_json="$2" expected="$3"
  local actual
  actual="$(printf '%s' "$relations_json" | jq -r '.[0].returnBehavior // "ABSENT"')"
  if [[ "$actual" != "$expected" ]]; then
    printf 'FAIL [%s]: expected returnBehavior="%s" got="%s"\nfull: %s\n' "$label" "$expected" "$actual" "$relations_json" >&2
    exit 1
  fi
  echo "PASS [$label]: returnBehavior=\"$expected\" preserved"
}

assert_no_returnBehavior() {
  local label="$1" relations_json="$2"
  if printf '%s' "$relations_json" | jq -e '.[0] | has("returnBehavior")' >/dev/null 2>&1; then
    local actual
    actual="$(printf '%s' "$relations_json" | jq -r '.[0].returnBehavior // "PRESENT"')"
    printf 'FAIL [%s]: expected NO returnBehavior field, got="%s"\nfull: %s\n' "$label" "$actual" "$relations_json" >&2
    exit 1
  fi
  echo "PASS [$label]: no returnBehavior injected (non-allow passed through)"
}

assert_rejects() {
  local label="$1" fixture_json="$2" fixture_file="$3" expected_diag="$4"
  local output status
  set +e
  output="$(eval_fixture "$fixture_json" "$fixture_file" 2>&1)"
  status=$?
  set -e
  if [[ "$status" -eq 0 ]]; then
    printf 'FAIL [%s]: expected rejection, but got: %s\n' "$label" "$output" >&2
    exit 1
  fi
  if ! grep -Fq "$expected_diag" <<<"$output"; then
    printf 'FAIL [%s]: expected diagnostic containing %q\ngot: %s\n' "$label" "$expected_diag" "$output" >&2
    exit 1
  fi
  echo "PASS [$label]: rejected with expected diagnostic"
}

# ── Temp dir for fixture files ──
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

export NFM_FIXTURE_FILE="${tmpdir}/fixture.json"

# ═══════════════════════════════════════════════════════════════
# Positive case 1: non-allow relations pass through unchanged
# ═══════════════════════════════════════════════════════════════
echo "=== Positive 1: non-allow relation passed through unchanged ==="
pos1_json='{"communicationContract":{"allowedRelations":[{"id":"deny-media","action":"deny","from":{"kind":"service","name":"media"},"to":{"kind":"external","uplinks":["wan"]},"trafficType":"any"}]}}'
pos1_out="$(eval_fixture "$pos1_json" "$NFM_FIXTURE_FILE")"
actual_action="$(printf '%s' "$pos1_out" | jq -r '.[0].action')"
if [[ "$actual_action" != "deny" ]]; then
  printf 'FAIL [P1]: non-allow relation action changed to "%s"\n' "$actual_action" >&2
  exit 1
fi
echo "PASS [P1]: non-allow relation passed through unchanged"

# ═══════════════════════════════════════════════════════════════
# Positive case 2: nested public-ingress stateful-return promoted
# ═══════════════════════════════════════════════════════════════
echo "=== Positive 2: nested stateful-return promoted to top-level ==="
pos2_json='{"communicationContract":{"allowedRelations":[{"id":"public-ingress-stateful","action":"allow","from":{"kind":"external","uplinks":["wan"]},"to":{"kind":"service","name":"media"},"trafficType":"any","publicIngressTupleAuthority":{"returnBehavior":"stateful-return"}}]}}'
pos2_out="$(eval_fixture "$pos2_json" "$NFM_FIXTURE_FILE")"
assert_returnBehavior_equals "P2: nested stateful-return promoted" "$pos2_out" "stateful-return"

# ═══════════════════════════════════════════════════════════════
# Seeded negative 1: missing tenant-to-WAN return behavior → REJECT
# (SMS-060: do not inject symmetric; reject incomplete tuple)
# ═══════════════════════════════════════════════════════════════
echo "=== Seeded negative 1: missing tenant-to-WAN return behavior → REJECT ==="
neg1_json='{"communicationContract":{"allowedRelations":[{"id":"tenant-to-wan-missing","action":"allow","from":{"kind":"tenant-set","name":"cameras"},"to":{"kind":"external","uplinks":["wan"]},"trafficType":"any"}]}}'
assert_rejects "N1: missing tenant-to-WAN return behavior" "$neg1_json" "$NFM_FIXTURE_FILE" \
  "missing returnBehavior on allow relation"

# Recovery: same relation with explicit one-way is accepted
echo "=== N1 recovery: explicit returnBehavior=\"one-way\" accepted ==="
neg1r_json='{"communicationContract":{"allowedRelations":[{"id":"tenant-to-wan-explicit","action":"allow","from":{"kind":"tenant-set","name":"cameras"},"to":{"kind":"external","uplinks":["wan"]},"trafficType":"any","returnBehavior":"one-way"}]}}'
neg1r_out="$(eval_fixture "$neg1r_json" "$NFM_FIXTURE_FILE")"
assert_returnBehavior_equals "N1 recovery: explicit one-way accepted" "$neg1r_out" "one-way"

# ═══════════════════════════════════════════════════════════════
# Seeded negative 2: explicit returnBehavior preserved verbatim
# (SMS-060: explicit values must not be overwritten)
# ═══════════════════════════════════════════════════════════════
echo "=== Seeded negative 2a: explicit returnBehavior=\"one-way\" preserved ==="
neg2a_json='{"communicationContract":{"allowedRelations":[{"id":"explicit-one-way","action":"allow","from":{"kind":"service","name":"media"},"to":{"kind":"external","uplinks":["wan"]},"trafficType":"any","returnBehavior":"one-way"}]}}'
neg2a_out="$(eval_fixture "$neg2a_json" "$NFM_FIXTURE_FILE")"
assert_returnBehavior_equals "N2a: explicit one-way preserved" "$neg2a_out" "one-way"

echo "=== Seeded negative 2b: explicit returnBehavior=\"symmetric\" preserved ==="
neg2b_json='{"communicationContract":{"allowedRelations":[{"id":"explicit-symmetric","action":"allow","from":{"kind":"service","name":"media"},"to":{"kind":"external","uplinks":["wan"]},"trafficType":"any","returnBehavior":"symmetric"}]}}'
neg2b_out="$(eval_fixture "$neg2b_json" "$NFM_FIXTURE_FILE")"
assert_returnBehavior_equals "N2b: explicit symmetric preserved" "$neg2b_out" "symmetric"

# ═══════════════════════════════════════════════════════════════
# Seeded negative 3: nested stateful-return preserved,
# not overwritten by injected symmetric
# (SMS-060: preserve applicable nested authority, don't inject)
# ═══════════════════════════════════════════════════════════════
echo "=== Seeded negative 3: nested stateful-return authority preserved ==="
neg3_json='{"communicationContract":{"allowedRelations":[{"id":"nested-only-stateful","action":"allow","from":{"kind":"external","uplinks":["wan"]},"to":{"kind":"service","name":"media"},"trafficType":"any","publicIngressTupleAuthority":{"returnBehavior":"stateful-return"}}]}}'
neg3_out="$(eval_fixture "$neg3_json" "$NFM_FIXTURE_FILE")"
assert_returnBehavior_equals "N3: nested stateful-return preserved" "$neg3_out" "stateful-return"

# ═══════════════════════════════════════════════════════════════
# Seeded negative 4: bidirectional=true does NOT substitute for
# explicit return authority → REJECT
# (SMS-060: bidirectional flag does not create return policy)
# ═══════════════════════════════════════════════════════════════
echo "=== Seeded negative 4: bidirectional=true without returnBehavior → REJECT ==="
neg4_json='{"communicationContract":{"allowedRelations":[{"id":"bidir-no-return","action":"allow","from":{"kind":"service","name":"media"},"to":{"kind":"service","name":"storage"},"trafficType":"streaming","bidirectional":true}]}}'
assert_rejects "N4: bidirectional without returnBehavior" "$neg4_json" "$NFM_FIXTURE_FILE" \
  "missing returnBehavior on allow relation"

# Recovery: same relation with explicit symmetric is accepted
echo "=== N4 recovery: bidirectional with explicit symmetric accepted ==="
neg4r_json='{"communicationContract":{"allowedRelations":[{"id":"bidir-explicit","action":"allow","from":{"kind":"service","name":"media"},"to":{"kind":"service","name":"storage"},"trafficType":"streaming","bidirectional":true,"returnBehavior":"symmetric"}]}}'
neg4r_out="$(eval_fixture "$neg4r_json" "$NFM_FIXTURE_FILE")"
assert_returnBehavior_equals "N4 recovery: bidirectional with explicit symmetric" "$neg4r_out" "symmetric"

# ═══════════════════════════════════════════════════════════════
# Additional: trafficType does NOT substitute for return authority
# ═══════════════════════════════════════════════════════════════
echo "=== TrafficType=\"any\" without returnBehavior → REJECT ==="
extra1_json='{"communicationContract":{"allowedRelations":[{"id":"any-no-return","action":"allow","from":{"kind":"service","name":"media"},"to":{"kind":"external","uplinks":["wan"]},"trafficType":"any"}]}}'
assert_rejects "trafficType=any without returnBehavior" "$extra1_json" "$NFM_FIXTURE_FILE" \
  "missing returnBehavior on allow relation"

pass_timed "FS-640-HDS-010-SDS-010-SMS-060-nfm-returnBehavior-injection-scoping" "${start_ms}"
