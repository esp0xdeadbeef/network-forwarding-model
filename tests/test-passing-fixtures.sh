#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
source "${repo_root}/tests/lib/timing.sh"
system="${NIX_SYSTEM:-$(nix eval --impure --raw --expr 'builtins.currentSystem')}"
max_jobs="${TEST_JOBS:-$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN)}"
if ! [[ "${max_jobs}" =~ ^[0-9]+$ ]] || [ "${max_jobs}" -lt 1 ]; then
  max_jobs=1
fi

resolve_examples_root() {
  local archive_json
  archive_json="$(mktemp)"

  nix flake archive --json "path:${repo_root}" > "${archive_json}"

  ARCHIVE_JSON="${archive_json}" nix eval --impure --raw --expr '
    let
      archived = builtins.fromJSON (builtins.readFile (builtins.getEnv "ARCHIVE_JSON"));
      labs = archived.inputs."network-labs" or null;
      labsPath = if labs == null then null else labs.path or null;
    in
      if labsPath == null then
        throw "tests: missing archived network-labs input path"
      else
        "${labsPath}/examples"
  '

  rm -f "${archive_json}"
}

examples_root="$(resolve_examples_root)"

resolve_fixtures_root() {
  local candidate

  for candidate in \
    "${repo_root}/tests/fixtures/passing" \
    "${repo_root}/tests/fixtures"
  do
    if [[ -d "${candidate}" ]] && find "${candidate}" -type f -name input.nix | grep -q .; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  return 1
}

fixtures_root="$(resolve_fixtures_root || true)"

log() {
  echo "==> $*"
}

fail() {
  echo "$1"
  exit 1
}

validate_output() {
  local name="$1"
  local output_json="$2"

  OUTPUT_JSON="${output_json}" nix eval --impure --expr '
    let
      data = builtins.fromJSON (builtins.readFile (builtins.getEnv "OUTPUT_JSON"));
      meta = data.meta.networkForwardingModel or { };
      enterprises = data.enterprise or { };
      enterpriseNames = builtins.attrNames enterprises;
      firstEnterprise = if enterpriseNames == [ ] then null else builtins.head enterpriseNames;
      firstSiteSet =
        if firstEnterprise == null then
          { }
        else
          (enterprises.${firstEnterprise}.site or { });
      siteNames = builtins.attrNames firstSiteSet;
    in
      builtins.isAttrs data
      && (meta.name or null) == "network-forwarding-model"
      && (meta.schemaVersion or null) == 9
      && builtins.isAttrs enterprises
      && enterpriseNames != [ ]
      && builtins.isAttrs firstSiteSet
      && siteNames != [ ]
  ' >/dev/null || fail "FAIL ${name}: validation failed"

}

run_direct_case() {
  local name="$1"
  local input_nix="$2"
  local case_start_ms
  case_start_ms="$(test_now_ms)"

  log "Running ${name}"

  local tmp_dir
  local expr

  tmp_dir="$(mktemp -d)"

  expr="let
    flake = builtins.getFlake (toString ${repo_root});
    input = import ${input_nix};
  in
    flake.libBySystem.\"${system}\".build { inherit input; }"

  nix eval --show-trace --impure --json --expr "${expr}" > "${tmp_dir}/out.json" \
    || {
      echo "--- INPUT (${name}) ---"
      cat "${input_nix}"
      fail "FAIL ${name}: evaluation failed"
    }

  validate_output "${name}" "${tmp_dir}/out.json"
  pass_timed "${name}" "${case_start_ms}"
  rm -rf "${tmp_dir}"
}

pids=()
names=()
logs=()

cleanup_workers() {
  local pid
  for pid in "${pids[@]:-}"; do
    if kill -0 "${pid}" 2>/dev/null; then
      kill "${pid}" 2>/dev/null || true
    fi
  done
}

trap 'cleanup_workers' EXIT INT TERM

running_jobs() {
  local count=0
  local pid
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

sanitize_name() {
  printf '%s\n' "$1" | tr '/ :' '---'
}

queue_case() {
  local name="$1"
  local input_nix="$2"
  local log_dir="$3"
  local log_file

  wait_for_slot
  log_file="${log_dir}/$(sanitize_name "${name}").log"
  run_direct_case "${name}" "${input_nix}" >"${log_file}" 2>&1 &
  pids+=("$!")
  names+=("${name}")
  logs+=("${log_file}")
}

wait_for_cases() {
  local failed=0
  local idx
  local pid
  local name
  local log_file

  for idx in "${!pids[@]}"; do
    pid="${pids[$idx]}"
    name="${names[$idx]}"
    log_file="${logs[$idx]}"

    if wait "${pid}"; then
      cat "${log_file}"
    else
      failed=$((failed + 1))
      cat "${log_file}" >&2
      echo "FAIL ${name}" >&2
    fi
  done

  pids=()
  names=()
  logs=()

  if [ "${failed}" -ne 0 ]; then
    fail "FAIL passing-fixtures: ${failed} case(s) failed"
  fi
}

run_local_passing_fixtures() {
  if [[ -z "${fixtures_root}" ]]; then
    log "Skipping local passing fixtures (missing fixtures roots with input.nix)"
    return 0
  fi

  log "Running local passing fixtures from ${fixtures_root}"
  local log_dir
  log_dir="$(mktemp -d)"

  while read -r input; do
    local dir
    local rel
    local name

    dir="${input%/*}"
    rel="${dir#${fixtures_root}/}"
    name="${rel}"

    if [[ "${name}" == "${dir}" || -z "${name}" ]]; then
      name="${dir##*/}"
    fi

    queue_case "fixture:${name}" "${input}" "${log_dir}"
  done < <(find "${fixtures_root}" -type f -name input.nix | sort)

  wait_for_cases
  rm -rf "${log_dir}"
}

run_external_examples() {
  if [[ ! -d "${examples_root}" ]]; then
    log "Skipping external examples (missing ${examples_root})"
    return 0
  fi

  log "Running external examples from ${examples_root}"
  local log_dir
  log_dir="$(mktemp -d)"

  while read -r dir; do
    local name
    local intent

    name="$(basename "${dir}")"
    intent="${dir}/intent.nix"

    [[ -f "${intent}" ]] || {
      echo "SKIP ${name} (no intent.nix)"
      continue
    }

    queue_network_labs_example "${name}" "${intent}" "${log_dir}"
  done < <(find "${examples_root}" -mindepth 1 -maxdepth 1 -type d | sort)

  wait_for_cases
  rm -rf "${log_dir}"
}

run_network_labs_example() {
  local name="$1"
  local intent="$2"
  local case_start_ms
  local tmp_dir
  local stderr_file
  local expr

  case_start_ms="$(test_now_ms)"
  log "Example ${name}"

  tmp_dir="$(mktemp -d)"
  stderr_file="${tmp_dir}/stderr.log"
  expr="let
    flake = builtins.getFlake (toString ${repo_root});
  in
    flake.libBySystem.\"${system}\".buildFromCompilerInputPath ${intent}"

  nix eval --show-trace --impure --json --expr "${expr}" > "${tmp_dir}/out.json" 2>"${stderr_file}" \
    || {
      echo "--- INTENT (${name}) ---"
      cat "${intent}"
      echo "--- STDERR (${name}) ---"
      cat "${stderr_file}"
      rm -rf "${tmp_dir}"
      fail "FAIL network-labs-example:${name}"
    }

  validate_output "network-labs-example:${name}" "${tmp_dir}/out.json"
  pass_timed "network-labs-example:${name}" "${case_start_ms}"
  rm -rf "${tmp_dir}"
}

queue_network_labs_example() {
  local name="$1"
  local intent="$2"
  local log_dir="$3"
  local log_file

  wait_for_slot
  log_file="${log_dir}/$(sanitize_name "network-labs-example:${name}").log"
  run_network_labs_example "${name}" "${intent}" >"${log_file}" 2>&1 &
  pids+=("$!")
  names+=("network-labs-example:${name}")
  logs+=("${log_file}")
}

run_local_passing_fixtures
run_external_examples
bash "${repo_root}/tests/test-hostile-dns-east-west.sh"

exit 0
