#!/usr/bin/env bash
set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

fail() {
  printf 'FAIL s88-structure-layout: %s\n' "$*" >&2
  exit 1
}

pass() {
  printf 'PASS s88-structure-layout\n'
}

required_dirs=(
  "s88/solver/Enterprise"
  "s88/solver/Site"
  "s88/solver/Unit"
  "s88/solver/EquipmentModule"
  "s88/solver/ControlModule"
)

for rel in "${required_dirs[@]}"; do
  if [ ! -d "${repo_root}/${rel}" ]; then
    fail "missing ${rel}"
  fi
done

assert_import_boundary() {
  local rel="$1"
  local non_import

  if [ ! -f "${repo_root}/${rel}" ]; then
    fail "missing compatibility entrypoint ${rel}"
  fi

  non_import="$(
    awk '
      /^[[:space:]]*$/ { next }
      /^[[:space:]]*#/ { next }
      /^[[:space:]]*[{][[:space:]]*lib[[:space:]]*[}][[:space:]]*:/ { next }
      /^[[:space:]]*import[[:space:]]/ { next }
      { print NR ":" $0 }
    ' "${repo_root}/${rel}"
  )"

  if [ "${non_import}" != "" ]; then
    fail "${rel} must be an import boundary only; unexpected content: ${non_import}"
  fi
}

assert_import_boundary "s88/solver/default.nix"
assert_import_boundary "s88/solver/site.nix"
assert_import_boundary "s88/solver/site/roles.nix"
assert_import_boundary "s88/solver/site/roles/input-role.nix"
assert_import_boundary "s88/solver/site/roles/validate.nix"
assert_import_boundary "s88/solver/site/wan.nix"
assert_import_boundary "s88/solver/site/enforcement.nix"
assert_import_boundary "s88/solver/site/transit-ordering.nix"
assert_import_boundary "s88/solver/site/topology/default.nix"
assert_import_boundary "s88/solver/site/topology/transit.nix"

pass
