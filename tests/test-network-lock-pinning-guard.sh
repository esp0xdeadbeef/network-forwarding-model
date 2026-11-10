#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: RTM-GUARD-NFM-LOCK-PINNING-001
# GAMP-SCOPE: guard-only; not SMT acceptance evidence
#
# A network-* flake input must stay pinned to its GitHub revision. A
# type = "path" lock entry for a network-* node silently swaps the pinned
# revision for a local checkout, which defeats the revision pinning the
# network-* spec chain depends on.
#
# The guard is proved discriminating here, against synthesized locks, so it
# keeps failing on a regression even while this repository's own gitignored
# flake.lock is regenerated. The live lock is a second, softer assertion: when
# a lock exists in the working tree it must also pass.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/timing.sh"
guard="${repo_root}/scripts/assert-network-lock-pinning.py"
tmpdir="$(mktemp -d -t network-lock-pinning.XXXXXX)"
trap 'rm -rf "${tmpdir}"' EXIT

fail() {
  echo "FAIL network-lock-pinning-guard: $*" >&2
  exit 1
}

cat >"${tmpdir}/good.lock" <<'JSON'
{
  "nodes": {
    "network-labs": {
      "locked": {
        "owner": "esp0xdeadbeef",
        "repo": "network-labs",
        "rev": "0123456789012345678901234567890123456789",
        "type": "github"
      }
    },
    "local-tool": {
      "locked": {
        "path": "/tmp/local-tool",
        "type": "path"
      }
    }
  }
}
JSON

python3 "${guard}" "${tmpdir}/good.lock" >/dev/null \
  || fail "pinned github network-* input plus non-network path input was rejected"

cat >"${tmpdir}/bad.lock" <<'JSON'
{
  "nodes": {
    "network-forwarding-model": {
      "locked": {
        "path": "/home/deadbeef/github/network-forwarding-model",
        "type": "path"
      }
    }
  }
}
JSON

if python3 "${guard}" "${tmpdir}/bad.lock" >"${tmpdir}/bad.out" 2>"${tmpdir}/bad.err"; then
  fail "network-* path lock unexpectedly passed"
fi

grep -F "network-forwarding-model.locked" "${tmpdir}/bad.err" >/dev/null \
  || fail "missing offending node in diagnostic"

if [[ -f "${repo_root}/flake.lock" ]]; then
  python3 "${guard}" "${repo_root}/flake.lock" >/dev/null \
    || fail "working-tree flake.lock contains network-* path inputs"
fi

pass_timed "network-lock-pinning-guard"
