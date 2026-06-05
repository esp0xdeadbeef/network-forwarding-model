#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: SMT-NFM-FS940-SOURCE-GROUP-CONTRACT-001
# GAMP-SCOPE: software-module-test

repo_root="$(git rev-parse --show-toplevel)"
source "${repo_root}/tests/lib/timing.sh"

fail() {
  echo "FAIL internal-route-source-group-contract: $*" >&2
  exit 1
}

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

archive_json="${tmpdir}/archive.json"
compiler_json="${tmpdir}/compiler.json"
base_model_json="${tmpdir}/base-model.json"
expr_nix="${tmpdir}/source-group-contract.nix"

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

S88_NFM_PROFILE_SKIP_INTERNAL_ROUTES=1 \
  REPO_FLAKE="path:${repo_root}" \
  COMPILER_JSON="${compiler_json}" \
  nix eval --extra-experimental-features 'nix-command flakes' --impure --json --expr '
    let
      nfm = builtins.getFlake (builtins.getEnv "REPO_FLAKE");
    in
      nfm.libBySystem.x86_64-linux.buildFromCompilerInputPath (builtins.getEnv "COMPILER_JSON")
  ' >"${base_model_json}"

cat >"${expr_nix}" <<'NIX'
      let
        flake = builtins.getFlake ("path:" + builtins.getEnv "REPO_ROOT");
        lib = flake.inputs.nixpkgs.lib // { network = flake.inputs.nixpkgs-network.lib.network; };
        baseModel = builtins.fromJSON (builtins.readFile (builtins.getEnv "BASE_MODEL_JSON"));
        internalRoutes = import (builtins.getEnv "REPO_ROOT" + "/implementation/lib/routing/internal-routes.nix") {
          inherit lib;
          self = flake;
        };
        sourceRows = import (builtins.getEnv "REPO_ROOT" + "/implementation/lib/routing/internal-routes/site-plan/source-rows.nix") {
          inherit lib;
        };
        site = baseModel.enterprise.esp0xdeadbeef.site."site-c";
        remotePrefixFacts = internalRoutes.buildRemotePrefixFacts site;
        rows = sourceRows.build {
          nodeNames = builtins.attrNames (site.nodes or { });
          nodes = site.nodes or { };
          inherit remotePrefixFacts;
          includeP2p = true;
          includeTenant = true;
          includeOverlay = true;
        };
      in
        {
          hasSourceRows = rows ? sourceRows;
          sourceRowsLength = if rows ? sourceRows then builtins.length rows.sourceRows else 0;
          remoteGroupCount = builtins.length (builtins.attrNames rows.remoteGroups);
          entriesByKind = builtins.length (rows.entriesByKind or [ ]);
        }
NIX

contract_json="$(
  REPO_ROOT="${repo_root}" BASE_MODEL_JSON="${base_model_json}" \
    nix eval --extra-experimental-features 'nix-command flakes' --impure --json --file "${expr_nix}"
)"

jq -e '
  (.entriesByKind > 0)
  and (.remoteGroupCount > 0)
  and ((.hasSourceRows | not) or (.sourceRowsLength == 0))
' <<<"${contract_json}" >/dev/null || {
  echo "${contract_json}" >&2
  fail "source-row planner still materializes an expanded sourceRows list"
}

pass_timed "internal-route-source-group-contract"
