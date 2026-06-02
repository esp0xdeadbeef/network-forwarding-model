#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: SMT-NFM-FS940-H2-INTERNAL-ROUTE-PROFILE-001
# GAMP-SCOPE: software-module-test

repo_root="$(git rev-parse --show-toplevel)"
source "${repo_root}/tests/lib/timing.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

archive_json="${tmpdir}/archive.json"
compiler_json="${tmpdir}/compiler.json"
full_json="${tmpdir}/full.json"
skip_internal_json="${tmpdir}/skip-internal.json"

nix flake archive --json "path:${repo_root}" >"${archive_json}"
labs_root="$(jq -er '.inputs["network-labs"].path' "${archive_json}")"
intent="${labs_root}/examples/s-router-overlay-dns-lane-policy/intent.nix"

nix eval \
  --extra-experimental-features 'nix-command flakes' \
  --impure \
  --json \
  --expr "
    let
      compiler = builtins.getFlake \"github:esp0xdeadbeef/network-compiler\";
      input = import \"${intent}\";
    in
      compiler.libBySystem.x86_64-linux.compile input
  " >"${compiler_json}"

eval_model() {
  local output_json="$1"
  local skip_internal="$2"
  if [[ "${skip_internal}" == "1" ]]; then
    S88_NFM_PROFILE_SKIP_INTERNAL_ROUTES=1 \
      REPO_ROOT="${repo_root}" COMPILER_JSON="${compiler_json}" \
      nix eval --extra-experimental-features 'nix-command flakes' --impure --json --expr '
        let
          flake = builtins.getFlake ("path:" + builtins.getEnv "REPO_ROOT");
          compiled = builtins.fromJSON (builtins.readFile (builtins.getEnv "COMPILER_JSON"));
        in
          flake.libBySystem.x86_64-linux.buildFromCompilerInputs { input = compiled; }
      ' >"${output_json}"
  else
    REPO_ROOT="${repo_root}" COMPILER_JSON="${compiler_json}" \
      nix eval --extra-experimental-features 'nix-command flakes' --impure --json --expr '
        let
          flake = builtins.getFlake ("path:" + builtins.getEnv "REPO_ROOT");
          compiled = builtins.fromJSON (builtins.readFile (builtins.getEnv "COMPILER_JSON"));
        in
          flake.libBySystem.x86_64-linux.buildFromCompilerInputs { input = compiled; }
      ' >"${output_json}"
  fi
}

start_ms="$(test_now_ms)"
eval_model "${skip_internal_json}" 1
skip_ms="$(( $(test_now_ms) - start_ms ))"

start_ms="$(test_now_ms)"
eval_model "${full_json}" 0
full_ms="$(( $(test_now_ms) - start_ms ))"

route_count() {
  jq '
    [
      .enterprise[]?.site[]?.nodes[]?.interfaces[]?.routes? as $routes
      | (($routes.ipv4 // []) | length) + (($routes.ipv6 // []) | length)
    ] | add // 0
  ' "$1"
}

skip_routes="$(route_count "${skip_internal_json}")"
full_routes="$(route_count "${full_json}")"
delta_ms="$((full_ms - skip_ms))"
delta_routes="$((full_routes - skip_routes))"

printf 'PROFILE internal-route-hypothesis full_ms=%s skip_internal_ms=%s delta_ms=%s full_routes=%s skip_internal_routes=%s delta_routes=%s\n' \
  "${full_ms}" "${skip_ms}" "${delta_ms}" "${full_routes}" "${skip_routes}" "${delta_routes}"

if [[ "${skip_ms}" -gt 3000 ]]; then
  echo "FAIL internal-route-profile-hypothesis: skip-internal baseline ${skip_ms}ms exceeds 3000ms" >&2
  exit 1
fi

if [[ "${delta_ms}" -lt 3000 ]]; then
  echo "FAIL internal-route-profile-hypothesis: internal-route delta ${delta_ms}ms is too small to support H2" >&2
  exit 1
fi

if [[ "${delta_routes}" -lt 1000 ]]; then
  echo "FAIL internal-route-profile-hypothesis: internal route delta ${delta_routes} routes is too small to support H2" >&2
  exit 1
fi

pass_timed "internal-route-profile-hypothesis"
