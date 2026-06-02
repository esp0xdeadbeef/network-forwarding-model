#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: SMT-NFM-FS940-SITE-PLAN-CONTRACT-001
# GAMP-SCOPE: software-module-test

repo_root="$(git rev-parse --show-toplevel)"
source "${repo_root}/tests/lib/timing.sh"

fail() {
  echo "FAIL internal-route-site-plan-contract: $*" >&2
  exit 1
}

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

archive_json="${tmpdir}/archive.json"
compiler_json="${tmpdir}/compiler.json"
expr_nix="${tmpdir}/site-plan-contract.nix"

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

cat >"${expr_nix}" <<'NIX'
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
        routeFacts = routeContext.buildFacts site;
        remotePrefixFacts = internalRoutes.buildRemotePrefixFacts site;
        plan = internalRoutes.buildSitePlan {
          topo = site;
          inherit routeContext routeFacts remotePrefixFacts;
        };
        plannedNodes = builtins.attrNames (plan.byNode or {});
        routeRowsForNode =
          nodePlan:
          builtins.foldl'
            (
              acc: linkPlan:
              acc + builtins.length (linkPlan.routes4 or [ ]) + builtins.length (linkPlan.routes6 or [ ])
            )
            0
            (builtins.attrValues nodePlan);
      in
        {
          inherit (plan) diagnostics;
          plannedNodeCount = builtins.length plannedNodes;
          materializedRouteRows =
            builtins.foldl'
              (acc: nodeName: acc + routeRowsForNode plan.byNode.${nodeName})
              0
              plannedNodes;
        }
NIX

contract_json="$(
  REPO_ROOT="${repo_root}" COMPILER_JSON="${compiler_json}" \
    nix eval --extra-experimental-features 'nix-command flakes' --impure --json --file "${expr_nix}"
)"

jq -e '
  (.diagnostics.routeAtoms.tenant > 0)
  and (.diagnostics.routeAtoms.p2p > 0)
  and (.diagnostics.sourceEligibilityPairs.tenant > 0)
  and (.diagnostics.sourceEligibilityPairs.p2p > 0)
  and (.diagnostics.planner == "scratch-site-wide")
  and (.diagnostics.usesExistingPerNodeExpansion == false)
  and (.diagnostics.nextHopIdentities > 0)
  and (.diagnostics.nodes > 0)
  and (.plannedNodeCount == .diagnostics.nodes)
  and (.materializedRouteRows > 100)
  and (.materializedRouteRows <= 350)
' <<<"${contract_json}" >/dev/null || {
  echo "${contract_json}" >&2
  fail "site-plan diagnostics are missing expected route atoms or eligibility pairs"
}

pass_timed "internal-route-site-plan-contract"
