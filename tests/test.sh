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
  test-semantic-lib-performance-boundary.sh
  test-internal-route-profile-hypothesis.sh
  test-internal-route-site-plan-contract.sh
  test-fs940-route-planner-child-atoms.sh
  test-internal-route-coordinator-contract.sh
  test-internal-route-source-group-contract.sh
  test-internal-route-equivalence-contract.sh
  test-overlay-interface-no-peer-null-duplicates.sh
  test-fs300-source-lane-route-metadata.sh
  test-fs300-ineligible-lane-route-rejection.sh
  test-overlay-route-source-lane-contract.sh
  test-aggregation-none-preserves-internal-prefixes.sh
  test-no-parent-relative-imports.sh
  test-emitter-provenance-repo-boundary.sh
  test-s88-structure-keywords.sh
  test-passing-fixtures.sh
  test-network-labs-output.sh
  test-failing-invariants.sh
  test-negative-forwarding.sh
  test-no-guessing.sh
  test-dedicated-lanes.sh
  test-p2p-link-realization.sh
  test-p2p-route-next-hop-peer-contract.sh
  test-access-tenant-gateway-host-addresses.sh
  test-tenant-client-attachments.sh
  test-p2p-specific-underlay-return-routes.sh
  test-deterministic-input-order.sh
  test-lane-naming-contract.sh
  test-lane-preserving-default-route-contract.sh
  test-ipv6-intent-preserved.sh
  test-runtime-gua-return-routes.sh
  test-lane-default-routes-policy-only.sh
  test-policy-source-scope-contract.sh
  test-fs360-downstream-client-public-prefix-authority.sh
  test-fs380-fs410-route-authority-handoff.sh
  test-fs350-prefix-authority-consumer-eligibility.sh
  test-fs390-public-ipv4-destination-policy.sh
  test-dns-service-node-placement.sh
  test-dns-service-requester-lane-routes.sh
  test-compiler-traffic-path-propagation.sh
  test-fs260-default-site-fabric-chain-handoff.sh
  test-adjacent-traffic-denial-handoff.sh
  test-network-labs-wildcard-path-handoff.sh
  test-network-labs-site-fabric-handoff.sh
  test-transit-ordering-deserializes-compiler-links.sh
  test-overlay-core-access-p2p-contract.sh
  test-overlay-underlay-access-default-routes.sh
  test-overlay-core-local-hostile-return-routes.sh
  test-transport-overlay-underlay-access-contract.sh
  test-overlay-access-uplink-defaults-without-core-default.sh
  test-overlay-access-uplink-lane-from-compiler-path.sh
  test-hostile-dedicated-east-west-lanes.sh
  test-tri-site-hostile-forwarding-scope.sh
  test-example-overlay-wan-return.sh
  test-overlay-peer-sites.sh
  test-external-ingress-uplink-defaults.sh
  test-service-source-uplink-lanes.sh
  test-dual-wan-branch-overlay.sh
  test-overlay-access-lane-warning.sh
  test-preferred-access-lanes.sh
  test-hostile-no-wan-core-reachability.sh
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
