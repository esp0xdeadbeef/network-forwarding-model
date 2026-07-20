#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-180-HDS-010-SDS-010-SMS-010
# GAMP-SCOPE: software-module-test
# Construction test for preservation of explicit nested return authority.

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
    printf 'FAIL [%s]: conflicting or invalid authority was accepted: %s\n' "$label" "$output" >&2
    exit 1
  fi
  grep -Fq "$expected" <<<"$output" || {
    printf 'FAIL [%s]: expected diagnostic %q\n%s\n' "$label" "$expected" "$output" >&2
    exit 1
  }
  echo "PASS [${label}]: rejected with expected diagnostic"
}

assert_accepts "explicit top-level authority preserved" \
  '[{"id":"explicit-one-way","action":"allow","returnBehavior":"one-way"}]' \
  '.[0].returnBehavior == "one-way"'
assert_accepts "nested public-ingress authority promoted" \
  '[{"id":"nested-stateful","action":"allow","publicIngressTupleAuthority":{"returnBehavior":"stateful-return"}}]' \
  '.[0].returnBehavior == "stateful-return" and .[0].publicIngressTupleAuthority.returnBehavior == "stateful-return"'
assert_accepts "matching authorities preserved" \
  '[{"id":"matching-stateful","action":"allow","returnBehavior":"stateful-return","publicIngressTupleAuthority":{"returnBehavior":"stateful-return"}}]' \
  '.[0].returnBehavior == "stateful-return" and .[0].publicIngressTupleAuthority.returnBehavior == "stateful-return"'

assert_rejects "conflicting authorities" \
  '[{"id":"conflicting-stateful","action":"allow","returnBehavior":"symmetric","publicIngressTupleAuthority":{"returnBehavior":"stateful-return"}}]' \
  "allow relation 'conflicting-stateful' has conflicting returnBehavior values 'symmetric' and 'stateful-return'"
assert_rejects "empty nested authority" \
  '[{"id":"empty-nested","action":"allow","publicIngressTupleAuthority":{"returnBehavior":""}}]' \
  "allow relation 'empty-nested' has an invalid publicIngressTupleAuthority.returnBehavior"

pass_timed "FS-180-HDS-010-SDS-010-SMS-010-nested-return-behavior-authority" "${start_ms}"
