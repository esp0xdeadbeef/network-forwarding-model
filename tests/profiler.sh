#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
source "${repo_root}/tests/lib/timing.sh"
system="${NFM_PROFILE_SYSTEM:-$(nix eval --impure --raw --expr builtins.currentSystem)}"
profile_dir="${NFM_PROFILE_DIR:-/tmp/network-forwarding-model-profiler}"
mkdir -p "${profile_dir}"

fail() {
  echo "$1" >&2
  exit 1
}

max_jobs="${NFM_PROFILE_JOBS:-${TEST_JOBS:-$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN)}}"
if ! [[ "${max_jobs}" =~ ^[0-9]+$ ]] || [ "${max_jobs}" -lt 1 ]; then
  max_jobs=1
fi

default_intents() {
  local archive_json labs_path
  archive_json="$(mktemp)"
  nix flake archive --json "path:${repo_root}" >"${archive_json}"
  labs_path="$(
    ARCHIVE_JSON="${archive_json}" nix eval --impure --raw --expr '
      let
        archived = builtins.fromJSON (builtins.readFile (builtins.getEnv "ARCHIVE_JSON"));
        labs = archived.inputs."network-labs" or null;
        path = if labs == null then null else labs.path or null;
      in
        if path == null then
          throw "profiler: missing archived network-labs input path"
        else
          path
    '
  )"
  rm -f "${archive_json}"
  printf '%s/examples/tri-site-dual-wan-overlay-integration-static/intent.nix\n' "${labs_path}"
  printf '%s/examples/s-router-overlay-dns-lane-policy/intent.nix\n' "${labs_path}"
}

if [ "$#" -gt 0 ]; then
  intent_paths=("$@")
else
  mapfile -t intent_paths < <(default_intents)
fi

for intent_path in "${intent_paths[@]}"; do
  [[ -f "${intent_path}" ]] || fail "FAIL profiler: missing intent ${intent_path}"
done

run_id="$(date -u +%Y%m%dT%H%M%SZ)-hostile-dns-east-west"
run_dir="${profile_dir}/${run_id}"
mkdir -p "${run_dir}"

summary_tsv="${run_dir}/summary.tsv"

elapsed_ms() {
  local start="$1"
  local end
  end="$(date +%s%3N)"
  printf '%s\n' "$((end - start))"
}

compile_once() {
  local intent_path="$1"
  local compiler_json="$2"
  local start
  start="$(date +%s%3N)"
  REPO_FLAKE="path:${repo_root}" \
    INTENT_PATH="${intent_path}" \
    NFM_PROFILE_SYSTEM="${system}" \
    nix eval --impure --json --expr '
      let
        system = builtins.getEnv "NFM_PROFILE_SYSTEM";
        nfm = builtins.getFlake (builtins.getEnv "REPO_FLAKE");
        compiler = nfm.inputs.network-compiler.libBySystem.${system};
        raw = import (builtins.getEnv "INTENT_PATH");
        input = if builtins.isFunction raw then raw { } else raw;
      in
        compiler.compile input
    ' >"${compiler_json}"
  elapsed_ms "${start}"
}

variants=(
  "full|all forwarding phases|"
  "skip-routing|topology without loopback/static routing|S88_NFM_PROFILE_SKIP_ROUTING=1"
  "skip-internal|static routing without internal route expansion|S88_NFM_PROFILE_SKIP_INTERNAL_ROUTES=1"
  "skip-p2p|internal routes without p2p remote prefixes|S88_NFM_PROFILE_SKIP_INTERNAL_P2P=1"
  "skip-tenant|internal routes without tenant remote prefixes|S88_NFM_PROFILE_SKIP_INTERNAL_TENANT=1"
  "skip-overlay|internal routes without overlay remote prefixes|S88_NFM_PROFILE_SKIP_INTERNAL_OVERLAY=1"
  "skip-invariants|full output without invariant checks|S88_NFM_PROFILE_SKIP_INVARIANTS=1"
  "skip-nearest|static routing without nearest-uplink defaults|S88_NFM_PROFILE_SKIP_NEAREST_DEFAULTS=1"
  "skip-lane-defaults|static routing without policy lane defaults|S88_NFM_PROFILE_SKIP_LANE_DEFAULTS=1"
  "skip-external-ingress|static routing without external ingress defaults|S88_NFM_PROFILE_SKIP_EXTERNAL_INGRESS_DEFAULTS=1"
  "skip-direct-wan|static routing without direct WAN defaults|S88_NFM_PROFILE_SKIP_DIRECT_WAN_DEFAULTS=1"
  "skip-uplink-learned|static routing without uplink-learned routes|S88_NFM_PROFILE_SKIP_UPLINK_LEARNED=1"
)

pids=()
names=()
logs=()

cleanup() {
  local pid
  for pid in "${pids[@]:-}"; do
    if kill -0 "${pid}" 2>/dev/null; then
      kill "${pid}" 2>/dev/null || true
    fi
  done
}
trap cleanup INT TERM

running_jobs() {
  local count=0 pid
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

profile_variant() {
  local example_name="$1"
  local compiler_json="$2"
  local name="$3"
  local description="$4"
  local env_spec="$5"
  local output_json="${run_dir}/${example_name}/${name}.json"
  local stderr_log="${run_dir}/${example_name}/${name}.stderr"
  local start ms
  start="$(date +%s%3N)"

  if [ -n "${env_spec}" ]; then
    env ${env_spec} REPO_FLAKE="path:${repo_root}" COMPILER_JSON="${compiler_json}" NFM_PROFILE_SYSTEM="${system}" \
      nix eval --impure --json --expr '
        let
          system = builtins.getEnv "NFM_PROFILE_SYSTEM";
          nfm = builtins.getFlake (builtins.getEnv "REPO_FLAKE");
        in
          nfm.libBySystem.${system}.buildFromCompilerInputPath (builtins.getEnv "COMPILER_JSON")
      ' >"${output_json}" 2>"${stderr_log}"
  else
    REPO_FLAKE="path:${repo_root}" COMPILER_JSON="${compiler_json}" NFM_PROFILE_SYSTEM="${system}" \
      nix eval --impure --json --expr '
        let
          system = builtins.getEnv "NFM_PROFILE_SYSTEM";
          nfm = builtins.getFlake (builtins.getEnv "REPO_FLAKE");
        in
          nfm.libBySystem.${system}.buildFromCompilerInputPath (builtins.getEnv "COMPILER_JSON")
      ' >"${output_json}" 2>"${stderr_log}"
  fi

  ms="$(elapsed_ms "${start}")"
  jq -r --arg name "${name}" --arg description "${description}" --arg ms "${ms}" '
    def sites: .enterprise[]?.site[]?;
    [
      $name,
      $description,
      $ms,
      ([sites.nodes | keys | length] | add // 0),
      ([sites.links | keys | length] | add // 0),
      ([sites.nodes[]?.interfaces[]?.routes.ipv4 // [] | length] | add // 0),
      ([sites.nodes[]?.interfaces[]?.routes.ipv6 // [] | length] | add // 0)
    ] | @tsv
  ' "${output_json}" >"${run_dir}/${example_name}/${name}.tsv"
}

printf 'Profiler output: %s\n' "${run_dir}"
printf 'Profiler jobs: %s\n' "${max_jobs}"
printf 'Profiler intents:\n'
printf '  %s\n' "${intent_paths[@]}"

: >"${summary_tsv}"

for intent_path in "${intent_paths[@]}"; do
  example_name="$(basename "$(dirname "${intent_path}")")"
  example_dir="${run_dir}/${example_name}"
  mkdir -p "${example_dir}"
  compiler_json="${example_dir}/compiler-output.json"
  compiler_ms="$(compile_once "${intent_path}" "${compiler_json}")"
  printf '%s\tcompiler\t%s\n' "${example_name}" "${compiler_ms}" >>"${summary_tsv}"
done

for intent_path in "${intent_paths[@]}"; do
  example_name="$(basename "$(dirname "${intent_path}")")"
  compiler_json="${run_dir}/${example_name}/compiler-output.json"
  for variant in "${variants[@]}"; do
    IFS='|' read -r name description env_spec <<<"${variant}"
    log="${run_dir}/${example_name}/${name}.log"
    wait_for_slot
    profile_variant "${example_name}" "${compiler_json}" "${name}" "${description}" "${env_spec}" >"${log}" 2>&1 &
    pids+=("$!")
    names+=("${example_name}:${name}")
    logs+=("${log}")
  done
done

failed=0
for idx in "${!pids[@]}"; do
  pid="${pids[$idx]}"
  name="${names[$idx]}"
  log="${logs[$idx]}"
  if wait "${pid}"; then
    example_name="${name%%:*}"
    phase_name="${name#*:}"
    sed "s/^/${example_name}\t/" "${run_dir}/${example_name}/${phase_name}.tsv" >>"${summary_tsv}"
  else
    failed=$((failed + 1))
    printf 'FAIL profiler:%s\n' "${name}" >&2
    sed "s/^/[${name}] /" "${log}" >&2
    example_name="${name%%:*}"
    phase_name="${name#*:}"
    if [ -f "${run_dir}/${example_name}/${phase_name}.stderr" ]; then
      sed "s/^/[${name}:stderr] /" "${run_dir}/${example_name}/${phase_name}.stderr" >&2
    fi
  fi
done

if [ "${failed}" -ne 0 ]; then
  printf 'FAIL profiler: %s variants failed\n' "${failed}" >&2
  exit 1
fi

{
  printf 'example\tphase\tdescription\tms\tnodes\tlinks\tipv4Routes\tipv6Routes\n'
  awk -F '\t' '
    $2 == "compiler" { print $1 "\t" $2 "\tcompiler output generation\t" $3 "\t\t\t\t"; next }
    { print }
  ' "${summary_tsv}" | sort -t $'\t' -k1,1 -k4,4n
} | tee "${run_dir}/summary.sorted.tsv"

pass_timed "profiler"
