#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: SMT-NFM-FS940-COORDINATOR-CONTRACT-001
# GAMP-SCOPE: software-module-test

repo_root="$(git rev-parse --show-toplevel)"
source "${repo_root}/tests/lib/timing.sh"

fail() {
  echo "FAIL internal-route-coordinator-contract: $*" >&2
  exit 1
}

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

archive_json="${tmpdir}/archive.json"
compiler_json="${tmpdir}/compiler.json"
plan_expr="${tmpdir}/site-plan-coordinator.nix"
coordinator_expr="${tmpdir}/coordinator-negative.nix"

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

cat >"${plan_expr}" <<'NIX'
let
  flake = builtins.getFlake ("path:" + builtins.getEnv "REPO_ROOT");
  compiled = builtins.fromJSON (builtins.readFile (builtins.getEnv "COMPILER_JSON"));
  nfmLib = flake.libBySystem.x86_64-linux;
  built = nfmLib.buildFromCompilerInputs { input = compiled; };
  site = built.enterprise.esp0xdeadbeef.site."site-c";
  internalRoutes = import (builtins.getEnv "REPO_ROOT" + "/implementation/lib/routing/internal-routes.nix") {
    lib = flake.inputs.nixpkgs.lib // { network = flake.inputs.nixpkgs-network.lib.network; };
    self = flake;
  };
  routeContext = import (builtins.getEnv "REPO_ROOT" + "/implementation/lib/routing/route-context.nix") {
    lib = flake.inputs.nixpkgs.lib // { network = flake.inputs.nixpkgs-network.lib.network; };
    self = flake;
  };
  plan = internalRoutes.buildSitePlan {
    topo = site;
    inherit routeContext;
  };
in
{
  completionRecords = plan.completionRecords;
  coordinator = plan.diagnostics.coordinator;
}
NIX

plan_json="$(
  REPO_ROOT="${repo_root}" COMPILER_JSON="${compiler_json}" \
    nix eval --extra-experimental-features 'nix-command flakes' --impure --json --file "${plan_expr}"
)"

jq -e '
  (.coordinator.coordinator == "FS-940-HDS-010-SDS-020-SMS-010")
  and (.coordinator.completionRecordCount == 7)
  and (.coordinator.expectedSubmoduleCount == 7)
  and (.coordinator.routeAtomAuthority == "FS-940-HDS-010-SDS-020-SMS-020")
  and (.coordinator.testedHypothesis == "H2 internal route expansion shared route group planner")
  and ([.completionRecords[].id] == [
    "FS-940-HDS-010-SDS-020-SMS-020",
    "FS-940-HDS-010-SDS-020-SMS-030",
    "FS-940-HDS-010-SDS-020-SMS-040",
    "FS-940-HDS-010-SDS-020-SMS-050",
    "FS-940-HDS-010-SDS-020-SMS-060",
    "FS-940-HDS-010-SDS-020-SMS-070",
    "FS-940-HDS-010-SDS-020-SMS-080"
  ])
  and all(.completionRecords[]; .completed == true and .coordinator == "FS-940-HDS-010-SDS-020-SMS-010")
' <<<"${plan_json}" >/dev/null || {
  echo "${plan_json}" >&2
  fail "site plan did not emit ordered coordinator completion records"
}

cat >"${coordinator_expr}" <<'NIX'
let
  coordinator = import (builtins.getEnv "REPO_ROOT" + "/implementation/lib/routing/internal-routes/site-plan/coordinator.nix") { };
  root = "FS-940-HDS-010-SDS-020";
  goodRecords = [
    { id = "${root}-SMS-020"; name = "route-atom-index"; claimsRouteAtomAuthority = true; recordCount = 3; }
    { id = "${root}-SMS-030"; name = "source-eligibility-matrix"; claimsRouteAtomAuthority = false; recordCount = 5; }
    { id = "${root}-SMS-040"; name = "next-hop-equivalence-table"; claimsRouteAtomAuthority = false; recordCount = 5; }
    { id = "${root}-SMS-050"; name = "forwarding-equivalence-group-planner"; claimsRouteAtomAuthority = false; recordCount = 5; }
    { id = "${root}-SMS-060"; name = "route-exception-layer"; claimsRouteAtomAuthority = false; recordCount = 0; }
    { id = "${root}-SMS-070"; name = "one-pass-route-materializer"; claimsRouteAtomAuthority = false; recordCount = 9; }
    { id = "${root}-SMS-080"; name = "route-cardinality-equivalence-diagnostics"; claimsRouteAtomAuthority = false; recordCount = 3; }
  ];
  build = records: coordinator.build {
    submoduleRecords = records;
    testedHypothesis = "focused coordinator negative test";
  };
  missing = builtins.tryEval (build (builtins.tail goodRecords));
  conflicting = builtins.tryEval (build (
    [ (builtins.head goodRecords) ((builtins.elemAt goodRecords 1) // { claimsRouteAtomAuthority = true; }) ]
    ++ builtins.tail (builtins.tail goodRecords)
  ));
  outOfOrder = builtins.tryEval (build (
    [ (builtins.head goodRecords) (builtins.elemAt goodRecords 2) (builtins.elemAt goodRecords 1) ]
    ++ builtins.tail (builtins.tail (builtins.tail goodRecords))
  ));
in
{
  missingFailed = !missing.success;
  conflictingFailed = !conflicting.success;
  outOfOrderFailed = !outOfOrder.success;
}
NIX

negative_json="$(
  REPO_ROOT="${repo_root}" \
    nix eval --extra-experimental-features 'nix-command flakes' --impure --json --file "${coordinator_expr}"
)"

jq -e '
  .missingFailed == true
  and .conflictingFailed == true
  and .outOfOrderFailed == true
' <<<"${negative_json}" >/dev/null || {
  echo "${negative_json}" >&2
  fail "coordinator did not fail missing, conflicting, and out-of-order submodule outputs"
}

pass_timed "internal-route-coordinator-contract"
