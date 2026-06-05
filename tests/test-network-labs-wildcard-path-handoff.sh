#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-180-HDS-010-SDS-010-SMS-030
# GAMP-ID: SMT-NFM-FS180-WILDCARD-HANDOFF-001
# GAMP-SCOPE: software-module-test

repo_root="$(git rev-parse --show-toplevel)"
source "${repo_root}/tests/lib/timing.sh"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

archive_json="${tmp_dir}/archive.json"
compiler_actual="${tmp_dir}/compiler.json"
nfm_actual="${tmp_dir}/nfm.json"

nix flake archive --json "path:${repo_root}" >"${archive_json}"
paths_json="$(
  ARCHIVE_JSON="${archive_json}" nix eval --impure --json --expr '
    let
      archived = builtins.fromJSON (builtins.readFile (builtins.getEnv "ARCHIVE_JSON"));
      compilerPath = archived.inputs."network-compiler".path or null;
      labsPath = archived.inputs."network-labs".path or null;
    in
      if compilerPath == null || labsPath == null then
        throw "network-labs wildcard handoff: missing network-compiler or network-labs input"
      else
        { compiler = compilerPath; labs = labsPath; }
  '
)"

compiler_path="$(printf '%s' "${paths_json}" | jq -r '.compiler')"
labs_path="$(printf '%s' "${paths_json}" | jq -r '.labs')"

collect_projection() {
  local example="$1"
  local input_json="$2"
  jq --arg example "${example}" '
    [
      .sites
      | to_entries[]
      | .key as $enterprise
      | .value
      | to_entries[]
      | .key as $site
      | .value.trafficPaths[]?
      | select(.destination == "any")
      | {
          example: $example,
          enterprise: $enterprise,
          site: $site,
          relationId,
          destination,
          stagePath,
          nodePath,
          nodePathAlternatives
        }
    ]
  ' "${input_json}"
}

collect_projection_nfm() {
  local example="$1"
  local input_json="$2"
  jq --arg example "${example}" '
    [
      .enterprise
      | to_entries[]
      | .key as $enterprise
      | .value.site
      | to_entries[]
      | .key as $site
      | .value.trafficPaths[]?
      | select(.destination == "any")
      | {
          example: $example,
          enterprise: $enterprise,
          site: $site,
          relationId,
          destination,
          stagePath,
          nodePath,
          nodePathAlternatives
        }
    ]
  ' "${input_json}"
}

compare_example() {
  local example="$1"
  local compiler_json="${tmp_dir}/${example}-compiler.json"
  local nfm_json_file="${tmp_dir}/${example}-nfm.json"

  nix run --no-warn-dirty --no-write-lock-file "path:${compiler_path}#compile" -- \
    "${labs_path}/examples/${example}/intent.nix" >"${compiler_json}"
  nix run "${repo_root}#compile-and-build-forwarding-model" -- \
    "${labs_path}/examples/${example}/intent.nix" >"${nfm_json_file}"
}

compiler_stream() {
  local example="$1"
  local compiler_json="${tmp_dir}/${example}-compiler.json"
  collect_projection "${example}" "${compiler_json}"
}

nfm_stream() {
  local example="$1"
  local nfm_json_file="${tmp_dir}/${example}-nfm.json"
  collect_projection_nfm "${example}" "${nfm_json_file}"
}

compare_example "ipv6-pd-downstream-delegation" >/dev/null
compare_example "single-wan-with-nebula-any-to-any-fw" >/dev/null
compare_example "tri-site-s-router-overlay-egress" >/dev/null

jq -s 'add | sort_by(.example, .enterprise, .site, .relationId)' \
  <(compiler_stream "ipv6-pd-downstream-delegation") \
  <(compiler_stream "single-wan-with-nebula-any-to-any-fw") \
  <(compiler_stream "tri-site-s-router-overlay-egress") \
  >"${compiler_actual}"

jq -s 'add | sort_by(.example, .enterprise, .site, .relationId)' \
  <(nfm_stream "ipv6-pd-downstream-delegation") \
  <(nfm_stream "single-wan-with-nebula-any-to-any-fw") \
  <(nfm_stream "tri-site-s-router-overlay-egress") \
  >"${nfm_actual}"

diff -u "${compiler_actual}" "${nfm_actual}"

jq -e '
  length > 0
  and all(.[];
    .destination == "any"
    and ((.nodePathAlternatives // []) | length) > 1
  )
' "${nfm_actual}" >/dev/null

pass_timed "network-labs-wildcard-path-handoff"
