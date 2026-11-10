#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-940-HDS-010-SDS-010-SMS-020
# GAMP-SCOPE: software-module-test
#
# FS-940 stage-timing diagnostic benchmark contract, scoped to this repository.
#
# NFM owns the "compiled semantic site model to forwarding model" benchmark
# entrypoint. SMS-020 requires that entrypoint to emit a benchmark record with
# the example name, elapsed time, diagnostic gate classification, locked
# repository revision, upstream/downstream cardinality, and command pass/fail
# status, and it must not fail solely because a phase-local timing threshold is
# exceeded.
#
# This is a contract guard over the benchmark source, so it runs without
# evaluating a lab source: it asserts the record fields the entrypoint emits and
# the documented threshold behaviour, and proves the assertion discriminates.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/timing.sh"
bench="${repo_root}/benchmarks/overlay-semantic-eval.sh"
tmpdir="$(mktemp -d -t fs940-sms020.XXXXXX)"
trap 'rm -rf "${tmpdir}"' EXIT

fail() {
  echo "FAIL FS-940-HDS-010-SDS-010-SMS-020: $*" >&2
  exit 1
}

[[ -f "${bench}" ]] || fail "missing stage benchmark entrypoint ${bench}"

# Required emitted record fields (SMS-020 Emitted Interfaces + Module
# Failure Conditions). Missing any one is a benchmark metadata failure.
required_fields=(
  "stage=network-forwarding-model"
  "example="
  "elapsed_ms="
  "threshold_ms="
  "gate=diagnostic"
  "repo_revision="
  "locked_revisions="
  "upstream_cardinality="
  "downstream_cardinality="
  "status=PASS"
  "status=FAIL"
  "excluded_runtime_stages="
)

check_fields() {
  local file="$1"
  local missing=0 field
  for field in "${required_fields[@]}"; do
    if ! rg -q --fixed-strings "${field}" "${file}"; then
      echo "FAIL FS-940-HDS-010-SDS-010-SMS-020: ${file} does not emit '${field}'" >&2
      missing=1
    fi
  done
  return "${missing}"
}

# ---- Positive: the live benchmark emits every required field ---------------
check_fields "${bench}" \
  || fail "overlay-semantic-eval.sh is missing required benchmark record fields"

# ---- Threshold behaviour: over-threshold is diagnostic, not a hard fail ----
# SMS-020: the module "shall not fail solely because stage-local elapsed time
# exceeds a phase-local timing threshold". It records OVER_THRESHOLD instead.
rg -q --fixed-strings "threshold_status=OVER_THRESHOLD" "${bench}" \
  || fail "over-threshold timing does not record threshold_status=OVER_THRESHOLD"
rg -q --fixed-strings 'gate=diagnostic' "${bench}" \
  || fail "benchmark gate is not classified diagnostic"

# The benchmark must still fail when the measured command itself fails.
rg -q --fixed-strings "status=FAIL" "${bench}" \
  || fail "benchmark does not emit status=FAIL for a failed measured command"

# ---- Seeded negative: a stripped record must be detected ------------------
grep -v --fixed-strings "locked_revisions=" "${bench}" >"${tmpdir}/stripped.sh"
if check_fields "${tmpdir}/stripped.sh" 2>/dev/null; then
  fail "seeded negative not detected: stripped locked_revisions= still passed"
fi

pass_timed "fs940-stage-benchmark-contract"
