#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
source "${repo_root}/tests/lib/timing.sh"
limit="${NIX_LOC_LIMIT:-200}"

mapfile -t oversized < <(
  cd "$repo_root"
  git ls-files -z \
    | xargs -0 -r wc -l \
    | awk -v limit="$limit" '
      $2 == "total" { next }
      $2 == "flake.lock" { next }
      $2 == "flake.nix" { next }
      $2 !~ /[.]nix$/ { next }
      $2 ~ /(^|\/)(tests?|fixtures)\// { next }
      $1 > limit { print $1 " " $2 }
    ' \
    | sort -nr
)

if ((${#oversized[@]} == 0)); then
  pass_timed "nix-file-loc"
  exit 0
fi

printf 'FAIL nix-file-loc: Nix implementation files over %s lines must be segmented by ownership.\n' "$limit" >&2
printf 'FAIL nix-file-loc: regression.md is not allowed to waive this; fix the layering instead.\n' >&2
printf 'FAIL nix-file-loc: flake.nix and flake.lock are excluded; implementation modules are not.\n' >&2
printf '%s\n' "${oversized[@]}" | sed 's/^/FAIL nix-file-loc:   /' >&2
exit 1
