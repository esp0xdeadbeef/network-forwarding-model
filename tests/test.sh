#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"

if [[ "${NETWORK_REPO_SWEEP:-0}" != "1" && "${NETWORK_REPO_DIRECT_TEST_OK:-0}" != "1" ]]; then
  echo "WARN: direct repo tests are partial; set NETWORK_REPO_DIRECT_TEST_OK=1 for intentional focused runs, or run network-codex-agent/scripts/s-router-test-rebuild-loop.sh for the locked full network-* sweep plus live validation." >&2
fi

max_jobs="${TEST_JOBS:-$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN)}"
if ! [[ "${max_jobs}" =~ ^[0-9]+$ ]] || [ "${max_jobs}" -lt 1 ]; then
  max_jobs=1
fi

tests=(
  test-nix-file-loc.sh
  test-s88-structure-layout.sh
  test-no-parent-relative-imports.sh
  test-s88-structure-keywords.sh
  test-passing-fixtures.sh
  test-network-labs-output.sh
  test-failing-invariants.sh
  test-negative-forwarding.sh
  test-no-guessing.sh
  test-dedicated-lanes.sh
  test-lane-naming-contract.sh
  test-lane-preserving-default-route-contract.sh
  test-lane-default-routes-policy-only.sh
  test-overlay-core-access-p2p-contract.sh
  test-overlay-peer-sites.sh
  test-external-ingress-uplink-defaults.sh
  test-dual-wan-branch-overlay.sh
  test-overlay-access-lane-warning.sh
  test-preferred-access-lanes.sh
)

tmpdir="$(mktemp -d)"
pids=()
names=()
logs=()

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

for test_name in "${tests[@]}"; do
  wait_for_slot

  log="${tmpdir}/${test_name}.log"
  (
    cd "${repo_root}"
    "tests/${test_name}"
  ) >"${log}" 2>&1 &

  pids+=("$!")
  names+=("${test_name}")
  logs+=("${log}")
done

failed=0

for idx in "${!pids[@]}"; do
  pid="${pids[$idx]}"
  name="${names[$idx]}"
  log="${logs[$idx]}"

  if wait "${pid}"; then
    printf 'PASS %s\n' "${name}"
  else
    status=$?
    failed=$((failed + 1))
    printf 'FAIL %s (exit %s)\n' "${name}" "${status}" >&2
  fi

  sed "s/^/[${name}] /" "${log}"
done

if [ "${failed}" -ne 0 ]; then
  printf 'FAIL tests: %s failed\n' "${failed}" >&2
  exit 1
fi

printf 'PASS tests\n'
