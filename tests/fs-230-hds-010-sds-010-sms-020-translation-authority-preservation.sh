#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-230-HDS-010-SDS-010-SMS-020
# GAMP-SCOPE: software-module-test
# Construction test: NFM preserves the structured public-ingress
# translation/source-preservation authority instead of leaving it opaque.
#   - translationMode = "none" is preserved as the explicit no-translation
#     decision (no rewriting, no defaulting to a translation-capable mode).
#   - Translation-capable modes are preserved together with their explicit
#     sourcePreservation binding.
#   - Invalid, unrecognized, or ambiguous translation fields fail closed with
#     a diagnostic naming the relation and the offending field.

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
    printf 'FAIL [%s]: invalid or ambiguous translation authority was accepted: %s\n' "$label" "$output" >&2
    exit 1
  fi
  grep -Fq "$expected" <<<"$output" || {
    printf 'FAIL [%s]: expected diagnostic %q\n%s\n' "$label" "$expected" "$output" >&2
    exit 1
  }
  echo "PASS [${label}]: rejected with expected diagnostic"
}

# Explicit no-translation decision preserved as structured data, not opaque:
# translationMode stays "none" and sourcePreservation stays bound.
assert_accepts "no-translation decision preserved" \
  '[{"id":"none-preserved","action":"allow","publicIngressTupleAuthority":{"returnBehavior":"stateful-return","translationMode":"none","sourcePreservation":"preserve-source"}}]' \
  '.[0].publicIngressTupleAuthority.translationMode == "none" and .[0].publicIngressTupleAuthority.sourcePreservation == "preserve-source" and .[0].returnBehavior == "stateful-return"'

# Translation-capable mode preserved with its explicit source binding.
assert_accepts "napt translation authority preserved" \
  '[{"id":"napt-preserved","action":"allow","publicIngressTupleAuthority":{"returnBehavior":"stateful-return","translationMode":"napt","sourcePreservation":"rewritten"}}]' \
  '.[0].publicIngressTupleAuthority.translationMode == "napt" and .[0].publicIngressTupleAuthority.sourcePreservation == "rewritten"'

# provider-port-forward vocabulary stays recognized (controlled SAT sources).
assert_accepts "provider-port-forward translation authority preserved" \
  '[{"id":"ppf-preserved","action":"allow","publicIngressTupleAuthority":{"returnBehavior":"stateful-return","translationMode":"provider-port-forward","sourcePreservation":"provider-napt"}}]' \
  '.[0].publicIngressTupleAuthority.translationMode == "provider-port-forward" and .[0].publicIngressTupleAuthority.sourcePreservation == "provider-napt"'

# Seeded negative: unrecognized translation mode fails closed, naming the
# relation and value instead of defaulting to a permissive mode.
assert_rejects "unrecognized translationMode" \
  '[{"id":"bad-mode","action":"allow","publicIngressTupleAuthority":{"returnBehavior":"stateful-return","translationMode":"hairpin-magic","sourcePreservation":"rewritten"}}]' \
  "FS-230-HDS-010-SDS-010-SMS-020: allow relation 'bad-mode' has an unrecognized publicIngressTupleAuthority.translationMode 'hairpin-magic'"

# Seeded negative: empty translation mode is invalid, not silently absent.
assert_rejects "empty translationMode" \
  '[{"id":"empty-mode","action":"allow","publicIngressTupleAuthority":{"returnBehavior":"stateful-return","translationMode":"","sourcePreservation":"rewritten"}}]' \
  "FS-230-HDS-010-SDS-010-SMS-020: allow relation 'empty-mode' has an invalid publicIngressTupleAuthority.translationMode"

# Seeded negative: translation requested without explicit source preservation
# is ambiguous source-address handling and must fail closed.
assert_rejects "translation without sourcePreservation" \
  '[{"id":"ambiguous-source","action":"allow","publicIngressTupleAuthority":{"returnBehavior":"stateful-return","translationMode":"napt"}}]' \
  "FS-230-HDS-010-SDS-010-SMS-020: allow relation 'ambiguous-source' requests translationMode 'napt' without an explicit publicIngressTupleAuthority.sourcePreservation"

# Seeded negative: unrecognized sourcePreservation fails closed.
assert_rejects "unrecognized sourcePreservation" \
  '[{"id":"bad-preservation","action":"allow","publicIngressTupleAuthority":{"returnBehavior":"stateful-return","translationMode":"napt","sourcePreservation":"maybe"}}]' \
  "FS-230-HDS-010-SDS-010-SMS-020: allow relation 'bad-preservation' has an unrecognized publicIngressTupleAuthority.sourcePreservation 'maybe'"

# Recovery: the no-translation tuple flipped to an explicit translation-capable
# mode with explicit source preservation is accepted unchanged.
assert_accepts "recovery: explicit selection accepted" \
  '[{"id":"none-preserved","action":"allow","publicIngressTupleAuthority":{"returnBehavior":"stateful-return","translationMode":"napt","sourcePreservation":"rewritten"}}]' \
  '.[0].publicIngressTupleAuthority.translationMode == "napt"'

pass_timed "fs-230-hds-010-sds-010-sms-020-translation-authority-preservation" "${start_ms}"
