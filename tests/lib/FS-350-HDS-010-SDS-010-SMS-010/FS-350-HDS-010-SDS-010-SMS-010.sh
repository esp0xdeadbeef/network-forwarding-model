#!/usr/bin/env bash
# GAMP-ID: FS-350-HDS-010-SDS-010-SMS-010
# GAMP-SCOPE: software-module-test
#
# Prefix subdivision authority: the consumer-eligibility test lives in this
# repository; the case wraps it so the trace is reachable from the catalog.
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
trace="FS-350-HDS-010-SDS-010-SMS-010"
test_path="${repo_root}/tests/test-fs350-prefix-authority-consumer-eligibility.sh"

[[ -f "${test_path}" ]] || {
  echo "FAIL ${trace}: missing construction test ${test_path}" >&2
  exit 1
}

(
  cd "${repo_root}"
  NETWORK_REPO_DIRECT_TEST_OK=1 bash "${test_path}"
) || {
  echo "FAIL ${trace}: NFM prefix authority consumer eligibility failed" >&2
  exit 1
}

echo "PASS ${trace}: prefix subdivision authority focused construction wrapper"
