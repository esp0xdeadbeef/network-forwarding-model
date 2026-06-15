#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-260-HDS-010-SDS-010-SMS-020
# GAMP-ID: FS-260-HDS-010-SDS-010-SMS-030
# GAMP-ID: SMT-NFM-FS260-SITE-FABRIC-HANDOFF-001
# GAMP-SCOPE: software-module-test

repo_root="$(git rev-parse --show-toplevel)"
source "${repo_root}/tests/lib/timing.sh"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT
system="${NIX_SYSTEM:-$(nix eval --impure --raw --expr 'builtins.currentSystem')}"

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
        throw "network-labs site fabric handoff: missing network-compiler or network-labs input"
      else
        { compiler = compilerPath; labs = labsPath; }
  '
)"

compiler_path="$(printf '%s' "${paths_json}" | jq -r '.compiler')"
labs_path="${repo_root}/tests/fixtures"

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
      | select(
          ($example == "s-router-overlay-dns-lane-policy" and (
            .relationId == "allow-tenants-to-uplinks"
            or .relationId == "allow-east-west-to-sitea-mgmt-dns"
          ))
          or ($example == "tri-site-s-router-overlay-egress" and .relationId == "allow-hostile-overlay-egress-to-wan")
          or ($example == "tri-site-dual-wan-overlay-integration-static" and (
            .relationId == "allow-sitec-storage-underlay-to-uplinks"
            or .relationId == "allow-sitec-storage-to-sitea-mgmt"
          ))
        )
      | {
          example: $example,
          enterprise: $enterprise,
          site: $site,
          relationId,
          stagePath,
          nodePath,
          nodePathAlternatives,
          corePathNodes,
          p2pIsolationKey,
          forbidsCoreToCoreP2P
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
      | select(
          ($example == "s-router-overlay-dns-lane-policy" and (
            .relationId == "allow-tenants-to-uplinks"
            or .relationId == "allow-east-west-to-sitea-mgmt-dns"
          ))
          or ($example == "tri-site-s-router-overlay-egress" and .relationId == "allow-hostile-overlay-egress-to-wan")
          or ($example == "tri-site-dual-wan-overlay-integration-static" and (
            .relationId == "allow-sitec-storage-underlay-to-uplinks"
            or .relationId == "allow-sitec-storage-to-sitea-mgmt"
          ))
        )
      | {
          example: $example,
          enterprise: $enterprise,
          site: $site,
          relationId,
          stagePath,
          nodePath,
          nodePathAlternatives,
          corePathNodes,
          p2pIsolationKey,
          forbidsCoreToCoreP2P
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

compare_example "s-router-overlay-dns-lane-policy"
compare_example "tri-site-s-router-overlay-egress"
compare_example "tri-site-dual-wan-overlay-integration-static"

jq -s 'add | sort_by(.example, .enterprise, .site, .relationId)' \
  <(collect_projection "s-router-overlay-dns-lane-policy" "${tmp_dir}/s-router-overlay-dns-lane-policy-compiler.json") \
  <(collect_projection "tri-site-s-router-overlay-egress" "${tmp_dir}/tri-site-s-router-overlay-egress-compiler.json") \
  <(collect_projection "tri-site-dual-wan-overlay-integration-static" "${tmp_dir}/tri-site-dual-wan-overlay-integration-static-compiler.json") \
  >"${compiler_actual}"

jq -s 'add | sort_by(.example, .enterprise, .site, .relationId)' \
  <(collect_projection_nfm "s-router-overlay-dns-lane-policy" "${tmp_dir}/s-router-overlay-dns-lane-policy-nfm.json") \
  <(collect_projection_nfm "tri-site-s-router-overlay-egress" "${tmp_dir}/tri-site-s-router-overlay-egress-nfm.json") \
  <(collect_projection_nfm "tri-site-dual-wan-overlay-integration-static" "${tmp_dir}/tri-site-dual-wan-overlay-integration-static-nfm.json") \
  >"${nfm_actual}"

diff -u "${compiler_actual}" "${nfm_actual}"

jq -e '
  [
    .[]
    | select(
        .example == "tri-site-s-router-overlay-egress"
        and .enterprise == "esp"
        and .site == "edge"
        and .relationId == "allow-hostile-overlay-egress-to-wan"
      )
  ][0]
  | .stagePath == [
      "core",
      "upstream-selector",
      "policy",
      "upstream-selector",
      "core"
    ]
    and .nodePath == [
      "edge-example-router-nebula-core",
      "edge-example-router-upstream",
      "edge-example-router-policy",
      "edge-example-router-upstream",
      "edge-example-router-core"
    ]
    and .forbidsCoreToCoreP2P == true
    and .p2pIsolationKey == "allow-hostile-overlay-egress-to-wan"
' "${nfm_actual}" >/dev/null

missing_roles_input="${tmp_dir}/missing-stage-role-identity.nix"
cat >"${missing_roles_input}" <<'NIX'
{
  sites = {
    acme = {
      ams = {
        addressPools = {
          local.ipv4 = "10.0.0.0/24";
          p2p.ipv4 = "10.0.1.0/24";
        };

        attachments = [
          {
            unit = "access";
            kind = "tenant";
            name = "client";
          }
        ];

        domains = {
          tenants = [
            {
              kind = "tenant";
              name = "client";
              ipv4 = "10.10.0.0/24";
            }
          ];
          externals = [
            {
              kind = "external";
              name = "wan";
            }
          ];
        };

        transit.ordering = [
          [ "access" "downstream" ]
          [ "downstream" "policy" ]
          [ "policy" "upstream" ]
          [ "upstream" "core" ]
        ];

        units = {
          access = { };
          downstream = { };
          policy = { };
          upstream = { };
          core = {
            uplinks.wan.ipv4 = [ "0.0.0.0/0" ];
          };
        };
      };
    };
  };
}
NIX

set +e
missing_roles_output="$(
  nix eval --impure --raw --expr "
    let
      flake = builtins.getFlake \"${repo_root}\";
      input = import \"${missing_roles_input}\";
      out = flake.libBySystem.\"${system}\".build { inherit input; };
    in
      if builtins.isAttrs out.enterprise.acme.site.ams then \"unexpected-ok\" else \"unexpected-shape\"
  " 2>&1
)"
missing_roles_rc=$?
set -e

if [[ "${missing_roles_rc}" -eq 0 ]]; then
  echo "FAIL missing-stage-role-identity: NFM accepted stage-like node names without explicit role identity" >&2
  exit 1
fi

if ! grep -q "missing required node role(s)" <<<"${missing_roles_output}"; then
  echo "FAIL missing-stage-role-identity: missing role validation diagnostic" >&2
  printf '%s\n' "${missing_roles_output}" >&2
  exit 1
fi

pass_timed "network-labs-site-fabric-handoff"
