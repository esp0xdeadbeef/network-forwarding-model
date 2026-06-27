#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: RTM-RUNNER-NFM-001
# GAMP-SCOPE: runner-only; not SMT acceptance evidence

repo_root="$(git rev-parse --show-toplevel)"
source "${repo_root}/tests/lib/timing.sh"

if [[ "${NETWORK_REPO_SWEEP:-0}" != "1" && "${NETWORK_REPO_DIRECT_TEST_OK:-0}" != "1" ]]; then
  echo "WARN: direct repo tests are partial; set NETWORK_REPO_DIRECT_TEST_OK=1 for intentional focused runs, or run network-codex-agent/scripts/s-router-full-lab-rebuild-loop.sh for the locked full network-* sweep plus live validation." >&2
fi

max_jobs="${TEST_JOBS:-$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN)}"
if ! [[ "${max_jobs}" =~ ^[0-9]+$ ]] || [ "${max_jobs}" -lt 1 ]; then
  max_jobs=1
fi

tests=(
  test-nix-file-loc.sh
  test-regression-md-resolved-states.sh
  test-s88-structure-layout.sh
  test-layer-entry-warning-contract.sh
  test-FS-940-HDS-010-SDS-010-SMS-070-nfm-semantic-lib-performance-boundary.sh
  test-FS-940-HDS-010-SDS-020-SMS-040-next-hop-equivalence-table.sh
  test-FS-940-HDS-010-SDS-020-SMS-080-route-cardinality-equivalence-diagnostics.sh
  test-no-parent-relative-imports.sh
  test-s88-structure-keywords.sh
  test-no-guessing.sh
  fs-300-hds-010-sds-010-sms-020.sh
  fs-300-hds-010-sds-010-sms-030.sh
  fs-370-hds-010-sds-010-sms-020.sh
  fs-370-hds-010-sds-010-sms-030.sh
  fs-370-hds-010-sds-010-sms-040.sh
  fs-370-hds-010-sds-010-sms-060.sh
  fs-370-hds-010-sds-010-sms-070.sh
  fs-370-hds-010-sds-010-sms-080.sh
  fs-370-hds-010-sds-010-sms-090.sh
  fs-370-hds-010-sds-010-sms-100.sh
  fs-360-hds-010-sds-010-sms-010.sh
  fs-360-hds-010-sds-010-sms-020.sh
  fs-360-hds-010-sds-010-sms-030.sh
  fs-380-hds-010-sds-010-sms-010.sh
  fs-480-hds-010-sds-010-sms-020.sh
  test-fs350-prefix-authority-consumer-eligibility.sh
  fs-390-hds-010-sds-010-sms-010.sh
  fs-390-hds-010-sds-010-sms-020.sh
  fs-390-hds-010-sds-010-sms-030.sh
  fs-410-hds-010-sds-010-sms-010.sh
  test-FS-380-HDS-010-SDS-010-SMS-020-nat44-egress.sh
  fs-260-hds-010-sds-010-sms-010.sh
  test-fs180-hds010-sds010-sms010-return-behavior-authority.sh
  fs-180-hds-010-sds-010-sms-030.sh
  test-network-labs-site-fabric-handoff.sh
  fs-180-hds-010-sds-010-sms-020.sh
  fs-460-hds-010-sds-010-sms-010.sh
  test-fs180-fs270-selector-relation-authority.sh
  test-fs250-core-role-minimal-authority.sh
  fs-350-hds-010-sds-010-sms-030.sh
  fs-500-hds-010-sds-010-sms-010-reachability-decision-classification.sh
  fs-500-hds-010-sds-010-sms-020-decision-type-preservation.sh
  fs-500-hds-010-sds-010-sms-030-decision-reason-diagnostic.sh
)

tmpdir="$(mktemp -d)"
pids=()
names=()
logs=()
elapsed_files=()

cleanup() {
  local pid
  for pid in "${pids[@]:-}"; do
    if kill -0 "${pid}" 2>/dev/null; then
      kill "${pid}" 2>/dev/null || true
    fi
  done
  rm -rf "${tmpdir}"
}
trap cleanup EXIT INT TERM

running_jobs() {
  local count=0
  local pid
  for pid in "${pids[@]:-}"; do
    if kill -0 "${pid}" 2>/dev/null; then
      count=$((count + 1))
    fi
  done
  printf '%s\n' "${count}"
}

wait_for_slot() {
  while [ "$(running_jobs)" -ge "${max_jobs}" ]; do
    sleep 0.2
  done
}

printf 'Running %s tests with TEST_JOBS=%s\n' "${#tests[@]}" "${max_jobs}"
suite_start_ms="$(date +%s%3N)"

for test_name in "${tests[@]}"; do
  wait_for_slot

  log="${tmpdir}/${test_name}.log"
  elapsed_file="${tmpdir}/${test_name}.elapsed"
  (
    child_start_ms="$(date +%s%3N)"
    cd "${repo_root}"
    status=0
    "tests/${test_name}" || status=$?
    child_end_ms="$(date +%s%3N)"
    printf '%s\n' "$((child_end_ms - child_start_ms))" >"${elapsed_file}"
    exit "${status}"
  ) >"${log}" 2>&1 &

  pids+=("$!")
  names+=("${test_name}")
  logs+=("${log}")
  elapsed_files+=("${elapsed_file}")
done

failed=0

for idx in "${!pids[@]}"; do
  pid="${pids[$idx]}"
  name="${names[$idx]}"
  log="${logs[$idx]}"
  elapsed_file="${elapsed_files[$idx]}"

  if wait "${pid}"; then
    elapsed_ms="$(cat "${elapsed_file}")"
    printf 'PASS %sms %s\n' "${elapsed_ms}" "${name}"
  else
    status=$?
    if [[ -f "${elapsed_file}" ]]; then
      elapsed_ms="$(cat "${elapsed_file}")"
    else
      elapsed_ms="unknown"
    fi
    failed=$((failed + 1))
    printf 'FAIL %sms %s (exit %s)\n' "${elapsed_ms}" "${name}" "${status}" >&2
    if [[ -f "${log}" ]]; then
      sed "s/^/[${name}] /" "${log}"
    else
      printf '[%s] log unavailable\n' "${name}" >&2
    fi
  fi
done

if [ "${failed}" -ne 0 ]; then
  printf 'FAIL tests: %s failed\n' "${failed}" >&2
  exit 1
fi

suite_end_ms="$(date +%s%3N)"
printf 'PASS %sms tests\n' "$((suite_end_ms - suite_start_ms))"
