#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-310-HDS-050-SDS-010-SMS-220
# GAMP-SCOPE: software-module-test
#
# Cross-repository test input pinning, scoped to this repository.
#
# Tests, scripts and runners must resolve other network-* repositories through
# the locked flake inputs, never through a local filesystem path such as a
# home-relative `~/github/network-*`, an absolute `/home/<user>/github/network-*`,
# or a sibling-checkout `..` + `/network-*` reference. A local path works only on
# one developer's machine, makes results path-dependent, and silently bypasses
# the revision pin in flake.lock.
#
# Intra-repository paths (`$(dirname "$0")/..`, `${repo_root}/tests/`) are the
# same repository and are permitted. `nix flake archive` JSON extraction of
# `inputs["<name>"].path` is the canonical pinned-input pattern and is
# permitted.
#
# The offending parent-directory token is assembled from its ASCII code so this
# detector does not itself trip the repository's parent-relative-import guard
# (tests/test-no-parent-relative-imports.sh).

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/timing.sh"
tmpdir="$(mktemp -d -t sms220-input-pinning.XXXXXX)"
trap 'rm -rf "${tmpdir}"' EXIT

fail() {
  echo "FAIL FS-310-HDS-050-SDS-010-SMS-220: $*" >&2
  exit 1
}

dotdot="$(printf '\x2e\x2e')"
parent_rel="${dotdot}/"
escaped_dotdot="${dotdot//./\\.}"
unpinned_re="(~/github/network-|/home/[^/]*/github/network-|${escaped_dotdot}/network-)"

scan_dir() {
  local dir="$1"
  # Exclude this test: it names the offending patterns in order to detect them.
  rg --no-heading --line-number --with-filename \
    --glob '!FS-310-HDS-050-SDS-010-SMS-220.sh' \
    --regexp "${unpinned_re}" \
    "${dir}" 2>/dev/null || true
}

# ---- Positive: this repository is clean -----------------------------------
{
  scan_dir "${repo_root}/tests"
  scan_dir "${repo_root}/scripts"
  scan_dir "${repo_root}/benchmarks"
  # Runners live at the repository root.
  rg --no-heading --line-number --with-filename --regexp "${unpinned_re}" \
    "${repo_root}"/*.sh 2>/dev/null || true
} >"${tmpdir}/violations.txt"

if [[ -s "${tmpdir}/violations.txt" ]]; then
  echo "FAIL FS-310-HDS-050-SDS-010-SMS-220: cross-repo references must use pinned flake inputs." >&2
  echo "FAIL FS-310-HDS-050-SDS-010-SMS-220: resolve siblings with 'nix flake archive' + inputs[\"<name>\"].path." >&2
  sed "s#${repo_root}/##; s/^/FAIL FS-310-HDS-050-SDS-010-SMS-220:   /" "${tmpdir}/violations.txt" >&2
  exit 1
fi

# ---- Seeded negatives: each unpinned form must be detected ----------------
declare -A cases=(
  [home-relative]='COMPILER_DIR=~/github/network-compiler'
  [absolute]='LABS=/home/example/github/network-labs'
  [sibling]="CPM=${parent_rel}network-control-plane-model"
)

for name in "${!cases[@]}"; do
  printf '#!/usr/bin/env bash\n%s\n' "${cases[${name}]}" >"${tmpdir}/${name}.sh"
  if ! rg -q --regexp "${unpinned_re}" "${tmpdir}/${name}.sh"; then
    fail "seeded negative '${name}' not detected: ${cases[${name}]}"
  fi
done

# ---- Recovery: a pinned flake-input form clears every pattern -------------
cat >"${tmpdir}/permitted.sh" <<'SH'
#!/usr/bin/env bash
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
compiler_root="$(jq -er '.inputs["network-compiler"].path' "${archive_json}")"
SH

if rg -q --regexp "${unpinned_re}" "${tmpdir}/permitted.sh"; then
  fail "permitted intra-repo and flake-archive paths were wrongly flagged"
fi

pass_timed "fs310-050-test-input-pinning"
