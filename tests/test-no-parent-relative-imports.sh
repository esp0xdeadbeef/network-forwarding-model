#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
source "${repo_root}/tests/lib/timing.sh"
tmp_file="$(mktemp)"
trap 'rm -f "${tmp_file}"' EXIT

rg \
  --no-heading \
  --line-number \
  --with-filename \
  --glob '!result/**' \
  --glob '!result-*' \
  --glob '!*.lock' \
  --glob '!tests/test-no-parent-relative-imports.sh' \
  --regexp '(\.\./){1,}' \
  "${repo_root}" \
  >"${tmp_file}" || true

if [ ! -s "${tmp_file}" ]; then
  pass_timed "no-parent-relative-imports"
  exit 0
fi

printf 'FAIL no-parent-relative-imports: found parent-relative paths.\n' >&2
printf 'FAIL no-parent-relative-imports: use self.outPath, an injected repository root, or an explicit module argument instead of parent-directory traversal.\n' >&2
sed "s#${repo_root}/##; s/^/FAIL no-parent-relative-imports:   /" "${tmp_file}" >&2
exit 1
