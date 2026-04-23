#!/usr/bin/env bash
set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

"${repo_root}/test-passing-fixtures.sh"
"${repo_root}/test-failing-invariants.sh"
"${repo_root}/test-no-guessing.sh"
"${repo_root}/test-dedicated-lanes.sh"
"${repo_root}/test-dual-wan-branch-overlay.sh"
"${repo_root}/test-preferred-access-lanes.sh"
