#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-940-HDS-010-SDS-020-SMS-010
# Construction test: Shared Route Group Planner Coordinator

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  echo "FAIL shared-route-group-planner-coordinator: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

require_cmd jq
require_cmd nix
require_cmd rg

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

write_case() {
  local path="$1"
  local records_expr="$2"
  local hypothesis_expr="$3"
  cat >"${path}" <<NIX
let
  coordinator = import ${repo_root}/implementation/lib/routing/internal-routes/site-plan/coordinator.nix { };
  records = ${records_expr};
  result = coordinator.build {
    siteId = "s-router";
    testedHypothesis = ${hypothesis_expr};
    submoduleRecords = records;
  };
in {
  expectedIds = coordinator.expectedIds;
  completionRecords = result.records;
  diagnostics = result.diagnostics;
}
NIX
}

canonical_records='[
  { id = "FS-940-HDS-010-SDS-020-SMS-020"; name = "route-atom-index"; claimsRouteAtomAuthority = true; recordCount = 11; }
  { id = "FS-940-HDS-010-SDS-020-SMS-030"; name = "source-eligibility-matrix"; claimsRouteAtomAuthority = false; recordCount = 7; }
  { id = "FS-940-HDS-010-SDS-020-SMS-040"; name = "next-hop-equivalence-table"; claimsRouteAtomAuthority = false; recordCount = 5; }
  { id = "FS-940-HDS-010-SDS-020-SMS-050"; name = "forwarding-equivalence-group-planner"; claimsRouteAtomAuthority = false; recordCount = 3; }
  { id = "FS-940-HDS-010-SDS-020-SMS-060"; name = "route-exception-layer"; claimsRouteAtomAuthority = false; recordCount = 1; }
  { id = "FS-940-HDS-010-SDS-020-SMS-070"; name = "one-pass-route-materializer"; claimsRouteAtomAuthority = false; recordCount = 13; }
  { id = "FS-940-HDS-010-SDS-020-SMS-080"; name = "route-cardinality-equivalence-diagnostics"; claimsRouteAtomAuthority = false; recordCount = 16; }
]'

happy_case="${tmp_dir}/happy.nix"
write_case "${happy_case}" "${canonical_records}" '"H2 internal route expansion shared route group planner"'
happy_json="$(nix eval --json -f "${happy_case}")" || fail "happy path evaluation failed"

jq -e '
  .expectedIds == [
    "FS-940-HDS-010-SDS-020-SMS-020",
    "FS-940-HDS-010-SDS-020-SMS-030",
    "FS-940-HDS-010-SDS-020-SMS-040",
    "FS-940-HDS-010-SDS-020-SMS-050",
    "FS-940-HDS-010-SDS-020-SMS-060",
    "FS-940-HDS-010-SDS-020-SMS-070",
    "FS-940-HDS-010-SDS-020-SMS-080"
  ]
  and (.completionRecords | length == 7)
  and all(.completionRecords[]; .completed == true and .coordinator == "FS-940-HDS-010-SDS-020-SMS-010")
  and (.diagnostics.coordinator == "FS-940-HDS-010-SDS-020-SMS-010")
  and (.diagnostics.completionRecordCount == 7)
  and (.diagnostics.expectedSubmoduleCount == 7)
  and (.diagnostics.routeAtomAuthority == "FS-940-HDS-010-SDS-020-SMS-020")
  and (.diagnostics.siteId == "s-router")
  and (.diagnostics.testedHypothesis == "H2 internal route expansion shared route group planner")
' <<<"${happy_json}" >/dev/null || fail "happy path did not emit ordered coordinator completion diagnostics"

assert_rejects() {
  local name="$1"
  local records_expr="$2"
  local hypothesis_expr="$3"
  local diagnostic_pattern="$4"
  local case_file="${tmp_dir}/${name}.nix"
  local out_file="${tmp_dir}/${name}.out"
  local err_file="${tmp_dir}/${name}.err"

  write_case "${case_file}" "${records_expr}" "${hypothesis_expr}"
  if nix eval --json -f "${case_file}" >"${out_file}" 2>"${err_file}"; then
    fail "${name} unexpectedly passed"
  fi
  rg -q -- "${diagnostic_pattern}" "${err_file}" \
    || fail "${name} did not emit expected diagnostic: ${diagnostic_pattern}"
}

# SN1: SMS-030 attempts to run without the required SMS-020 route atom output.
assert_rejects \
  "missing-sms020" \
  '[
    { id = "FS-940-HDS-010-SDS-020-SMS-030"; name = "source-eligibility-matrix"; claimsRouteAtomAuthority = false; }
    { id = "FS-940-HDS-010-SDS-020-SMS-040"; name = "next-hop-equivalence-table"; claimsRouteAtomAuthority = false; }
    { id = "FS-940-HDS-010-SDS-020-SMS-050"; name = "forwarding-equivalence-group-planner"; claimsRouteAtomAuthority = false; }
    { id = "FS-940-HDS-010-SDS-020-SMS-060"; name = "route-exception-layer"; claimsRouteAtomAuthority = false; }
    { id = "FS-940-HDS-010-SDS-020-SMS-070"; name = "one-pass-route-materializer"; claimsRouteAtomAuthority = false; }
    { id = "FS-940-HDS-010-SDS-020-SMS-080"; name = "route-cardinality-equivalence-diagnostics"; claimsRouteAtomAuthority = false; }
  ]' \
  '"H2 internal route expansion shared route group planner"' \
  'missing required submodule output FS-940-HDS-010-SDS-020-SMS-020'

# Recovery for SN1 is the canonical happy path above. This additional seeded
# order negative proves a present SMS-020 cannot appear after SMS-030.
assert_rejects \
  "out-of-order-sms020" \
  '[
    { id = "FS-940-HDS-010-SDS-020-SMS-030"; name = "source-eligibility-matrix"; claimsRouteAtomAuthority = false; }
    { id = "FS-940-HDS-010-SDS-020-SMS-020"; name = "route-atom-index"; claimsRouteAtomAuthority = true; }
    { id = "FS-940-HDS-010-SDS-020-SMS-040"; name = "next-hop-equivalence-table"; claimsRouteAtomAuthority = false; }
    { id = "FS-940-HDS-010-SDS-020-SMS-050"; name = "forwarding-equivalence-group-planner"; claimsRouteAtomAuthority = false; }
    { id = "FS-940-HDS-010-SDS-020-SMS-060"; name = "route-exception-layer"; claimsRouteAtomAuthority = false; }
    { id = "FS-940-HDS-010-SDS-020-SMS-070"; name = "one-pass-route-materializer"; claimsRouteAtomAuthority = false; }
    { id = "FS-940-HDS-010-SDS-020-SMS-080"; name = "route-cardinality-equivalence-diagnostics"; claimsRouteAtomAuthority = false; }
  ]' \
  '"H2 internal route expansion shared route group planner"' \
  'out-of-order submodule output at position 1; expected FS-940-HDS-010-SDS-020-SMS-020, got FS-940-HDS-010-SDS-020-SMS-030'

# SN2: duplicate authority over route atoms is rejected.
assert_rejects \
  "conflicting-authority" \
  '[
    { id = "FS-940-HDS-010-SDS-020-SMS-020"; name = "route-atom-index"; claimsRouteAtomAuthority = true; }
    { id = "FS-940-HDS-010-SDS-020-SMS-030"; name = "source-eligibility-matrix"; claimsRouteAtomAuthority = false; }
    { id = "FS-940-HDS-010-SDS-020-SMS-040"; name = "next-hop-equivalence-table"; claimsRouteAtomAuthority = true; }
    { id = "FS-940-HDS-010-SDS-020-SMS-050"; name = "forwarding-equivalence-group-planner"; claimsRouteAtomAuthority = false; }
    { id = "FS-940-HDS-010-SDS-020-SMS-060"; name = "route-exception-layer"; claimsRouteAtomAuthority = false; }
    { id = "FS-940-HDS-010-SDS-020-SMS-070"; name = "one-pass-route-materializer"; claimsRouteAtomAuthority = false; }
    { id = "FS-940-HDS-010-SDS-020-SMS-080"; name = "route-cardinality-equivalence-diagnostics"; claimsRouteAtomAuthority = false; }
  ]' \
  '"H2 internal route expansion shared route group planner"' \
  'conflicting route atom authority surfaces'

assert_rejects \
  "missing-hypothesis" \
  "${canonical_records}" \
  '""' \
  'missing tested hypothesis'

echo "PASS FS-940-HDS-010-SDS-020-SMS-010 shared route group planner coordinator"
