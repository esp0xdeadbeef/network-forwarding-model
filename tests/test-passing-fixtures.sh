#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
system="${NIX_SYSTEM:-$(nix eval --impure --raw --expr 'builtins.currentSystem')}"

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
    "${repo_root}/fixtures/passing" \
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

  echo "PASS ${name}"
}

run_direct_case() {
  local name="$1"
  local input_nix="$2"

  log "Running ${name}"

  local tmp_dir
  local expr

  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "'"${tmp_dir}"'"' RETURN

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
  rm -rf "${tmp_dir}"
  trap - RETURN
}

run_local_passing_fixtures() {
  if [[ -z "${fixtures_root}" ]]; then
    log "Skipping local passing fixtures (missing fixtures roots with input.nix)"
    return 0
  fi

  log "Running local passing fixtures from ${fixtures_root}"

  while read -r input; do
    local dir
    local rel
    local name

    dir="$(dirname "${input}")"
    rel="${dir#${fixtures_root}/}"
    name="${rel}"

    if [[ "${name}" == "${dir}" || -z "${name}" ]]; then
      name="$(basename "${dir}")"
    fi

    run_direct_case "fixture:${name}" "${input}"
  done < <(find "${fixtures_root}" -type f -name input.nix | sort)
}

run_external_examples() {
  if [[ ! -d "${examples_root}" ]]; then
    log "Skipping external examples (missing ${examples_root})"
    return 0
  fi

  log "Running external examples from ${examples_root}"

  while read -r dir; do
    local name
    local intent
    local tmp_dir
    local stderr_file
    local expr

    name="$(basename "${dir}")"
    intent="${dir}/intent.nix"

    [[ -f "${intent}" ]] || {
      echo "SKIP ${name} (no intent.nix)"
      continue
    }

    log "Example ${name}"

    tmp_dir="$(mktemp -d)"
    stderr_file="${tmp_dir}/stderr.log"
    trap 'rm -rf "'"${tmp_dir}"'"' RETURN

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
        fail "FAIL network-labs-example:${name}"
      }

    validate_output "network-labs-example:${name}" "${tmp_dir}/out.json"
    rm -rf "${tmp_dir}"
    trap - RETURN
  done < <(find "${examples_root}" -mindepth 1 -maxdepth 1 -type d | sort)
}

run_local_passing_fixtures
run_external_examples

exit 0
