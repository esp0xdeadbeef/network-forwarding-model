#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-180-HDS-010-SDS-010-SMS-040
# GAMP-SCOPE: software-module-test
# Construction test for Negative case 3: an unrecognized returnBehavior value
# (e.g. "asymmetric", "hairpin", "unknown") must be rejected with a diagnostic
# naming the unrecognized value and the affected relation ID. It must NOT be
# silently treated as absent/one-way. Recognized vocabulary:
#   symmetric | one-way | stateful-return

repo_root="$(git rev-parse --show-toplevel)"
source "${repo_root}/tests/lib/timing.sh"

start_ms="$(test_now_ms)"
tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT
export NFM_REPO_ROOT="${repo_root}"
export NFM_RELATIONS_FILE="${tmpdir}/relations.json"

eval_relations() {
  local relations_json="$1"
  printf '%s' "$relations_json" >"${NFM_RELATIONS_FILE}"
  nix eval --impure --json --expr '
    let
      repoRoot = builtins.getEnv "NFM_REPO_ROOT";
      attrs = import (repoRoot + "/implementation/lib/attrs.nix");
      shape = import (repoRoot + "/compiler-input/sites/shape.nix") {
        inherit (attrs) getAttrPathOr hasAttrPath;
      };
      relations = builtins.fromJSON (builtins.readFile (builtins.getEnv "NFM_RELATIONS_FILE"));
    in
      (shape.normalizeCommunicationContract {
        communicationContract.allowedRelations = relations;
      }).allowedRelations
  '
}

assert_accepts() {
  local label="$1" relations_json="$2" expected="$3"
  local output
  output="$(eval_relations "$relations_json")"
  printf '%s' "$output" | jq -e "$expected" >/dev/null || {
    printf 'FAIL [%s]: unexpected normalized relations: %s\n' "$label" "$output" >&2
    exit 1
  }
  echo "PASS [${label}]"
}

assert_rejects() {
  local label="$1" relations_json="$2" expected="$3"
  local output status
  set +e
  output="$(eval_relations "$relations_json" 2>&1)"
  status=$?
  set -e
  if [[ "$status" -eq 0 ]]; then
    printf 'FAIL [%s]: unrecognized returnBehavior was silently accepted: %s\n' "$label" "$output" >&2
    exit 1
  fi
  grep -Fq "$expected" <<<"$output" || {
    printf 'FAIL [%s]: expected diagnostic %q\n%s\n' "$label" "$expected" "$output" >&2
    exit 1
  }
  echo "PASS [${label}]: rejected with expected diagnostic"
}

# Recognized vocabulary stays accepted (no regression of SMS-010/SMS-060 behavior).
assert_accepts "recognized symmetric preserved" \
  '[{"id":"rel-symmetric","action":"allow","returnBehavior":"symmetric"}]' \
  '.[0].returnBehavior == "symmetric"'
assert_accepts "recognized one-way preserved" \
  '[{"id":"rel-one-way","action":"allow","returnBehavior":"one-way"}]' \
  '.[0].returnBehavior == "one-way"'
assert_accepts "recognized nested stateful-return promoted" \
  '[{"id":"rel-nested","action":"allow","publicIngressTupleAuthority":{"returnBehavior":"stateful-return"}}]' \
  '.[0].returnBehavior == "stateful-return"'
# Non-allow relations are untouched even with unrecognized values.
assert_accepts "deny relation not evaluated for return vocabulary" \
  '[{"id":"rel-deny","action":"deny","returnBehavior":"asymmetric"}]' \
  '.[0].returnBehavior == "asymmetric"'

# Negative case 3: unrecognized values rejected with value + relation ID.
assert_rejects "top-level asymmetric rejected" \
  '[{"id":"rel-bad-asymmetric","action":"allow","returnBehavior":"asymmetric"}]' \
  "FS-180-HDS-010-SDS-010-SMS-040: allow relation 'rel-bad-asymmetric' has an unrecognized top-level returnBehavior 'asymmetric'"
assert_rejects "top-level hairpin rejected" \
  '[{"id":"rel-bad-hairpin","action":"allow","returnBehavior":"hairpin"}]' \
  "FS-180-HDS-010-SDS-010-SMS-040: allow relation 'rel-bad-hairpin' has an unrecognized top-level returnBehavior 'hairpin'"
assert_rejects "top-level unknown rejected" \
  '[{"id":"rel-bad-unknown","action":"allow","returnBehavior":"unknown"}]' \
  "FS-180-HDS-010-SDS-010-SMS-040: allow relation 'rel-bad-unknown' has an unrecognized top-level returnBehavior 'unknown'"
assert_rejects "nested asymmetric rejected" \
  '[{"id":"rel-bad-nested","action":"allow","publicIngressTupleAuthority":{"returnBehavior":"asymmetric"}}]' \
  "FS-180-HDS-010-SDS-010-SMS-040: allow relation 'rel-bad-nested' has an unrecognized publicIngressTupleAuthority returnBehavior 'asymmetric'"

# SMS-010 fail-closed diagnostics for invalid/empty values stay intact.
assert_rejects "empty top-level still invalid (SMS-010)" \
  '[{"id":"rel-empty","action":"allow","returnBehavior":""}]' \
  "allow relation 'rel-empty' has an invalid top-level returnBehavior"

pass_timed "fs-180-hds-010-sds-010-sms-040-unrecognized-return-behavior" "${start_ms}"
