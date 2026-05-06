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
  "s88/Enterprise"
  "s88/Site"
  "s88/Unit"
  "s88/ControlModule"
  "s88/ControlModule/enforcement"
  "s88/Unit/core"
  "s88/Unit/roles"
)

for rel in "${required_dirs[@]}"; do
  if [ ! -d "${repo_root}/${rel}" ]; then
    fail "missing ${rel}"
  fi
done

if [ -e "${repo_root}/s88/site.nix" ] || [ -e "${repo_root}/s88/site" ]; then
  fail "lowercase s88/site compatibility entrypoints must stay out of the active S88 tree"
fi

if [ -e "${repo_root}/s88/default.nix" ]; then
  fail "s88/default.nix hides the public boundary; use s88/build.nix"
fi

if [ ! -f "${repo_root}/s88/build.nix" ]; then
  fail "missing public build entrypoint s88/build.nix"
fi

if [ ! -f "${repo_root}/s88/Enterprise/build.nix" ]; then
  fail "missing enterprise dispatcher s88/Enterprise/build.nix"
fi

if [ ! -f "${repo_root}/s88/ControlModule/enforcement/build.nix" ]; then
  fail "missing control-module enforcement builder s88/ControlModule/enforcement/build.nix"
fi

if [ ! -f "${repo_root}/s88/Unit/roles/build.nix" ]; then
  fail "missing unit role builder s88/Unit/roles/build.nix"
fi

if [ -e "${repo_root}/s88/Input" ]; then
  fail "input normalization is not an S88 physical/equipment layer"
fi

if [ ! -f "${repo_root}/compiler-input/sites/build.nix" ]; then
  fail "missing compiler input site-set normalizer compiler-input/sites/build.nix"
fi

pass
