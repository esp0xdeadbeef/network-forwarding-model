#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: SMT-NFM-FS940-ROUTE-PLANNER-CHILD-ATOMS-001
# GAMP-SCOPE: software-module-test

repo_root="$(git rev-parse --show-toplevel)"
source "${repo_root}/tests/lib/timing.sh"

fail() {
  echo "FAIL fs940-route-planner-child-atoms: $*" >&2
  exit 1
}

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

archive_json="${tmpdir}/archive.json"
compiler_json="${tmpdir}/compiler.json"
expr_nix="${tmpdir}/fs940-route-planner-child-atoms.nix"

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
  lib = flake.inputs.nixpkgs.lib // { network = flake.inputs.nixpkgs-network.lib.network; };
  nfmLib = flake.libBySystem.x86_64-linux;
  built = nfmLib.buildFromCompilerInputs { input = compiled; };
  site = built.enterprise.esp0xdeadbeef.site."site-c";
  internalRoutes = import (builtins.getEnv "REPO_ROOT" + "/implementation/lib/routing/internal-routes.nix") {
    inherit lib;
    self = flake;
  };
  routeContext = import (builtins.getEnv "REPO_ROOT" + "/implementation/lib/routing/route-context.nix") {
    inherit lib;
    self = flake;
  };
  plan = internalRoutes.buildSitePlan {
    topo = site;
    inherit routeContext;
  };
in
{
  inherit (plan) diagnostics completionRecords;
}
NIX

contract_json="$(
  REPO_ROOT="${repo_root}" COMPILER_JSON="${compiler_json}" \
    nix eval --extra-experimental-features 'nix-command flakes' --impure --json --file "${expr_nix}"
)"

jq -e '
  def required_sms: [
    "FS-940-HDS-010-SDS-020-SMS-020",
    "FS-940-HDS-010-SDS-020-SMS-030",
    "FS-940-HDS-010-SDS-020-SMS-040",
    "FS-940-HDS-010-SDS-020-SMS-050",
    "FS-940-HDS-010-SDS-020-SMS-060",
    "FS-940-HDS-010-SDS-020-SMS-070",
    "FS-940-HDS-010-SDS-020-SMS-080"
  ];

  ((.completionRecords | map(.id)) == required_sms)
  and all(.completionRecords[]; .completed == true and .coordinator == "FS-940-HDS-010-SDS-020-SMS-010")

  and (.diagnostics.routeAtomIndex.sms == "FS-940-HDS-010-SDS-020-SMS-020")
  and (.diagnostics.routeAtomIndex.builtBeforeRouteRows == true)
  and (.diagnostics.routeAtomIndex.atomCount > 0)
  and (.diagnostics.routeAtomIndex.atomCount == (
    .diagnostics.routeAtoms.tenant + .diagnostics.routeAtoms.overlay + .diagnostics.routeAtoms.p2p
  ))
  and all(.diagnostics.routeAtomIndex.atoms[];
    (.id // "") != ""
    and (.family == 4 or .family == 6)
    and ((.destination // null) != null or (.sourceFile // null) != null)
    and ((.owner // null) != null)
    and ((.kind // null) != null)
    and (.aggregationClass as $class | ["exact-only", "exact-dedupe", "prefix-summary-eligible", "runtime-source-file"] | index($class))
    and (.exceptionClass as $class | ["none", "point-to-point-exact", "runtime-source-file", "overlay-scope-exact", "selected-uplink-exact"] | index($class))
  )
  and ((.diagnostics.routeAtomIndex.aggregationClasses["exact-only"] // 0) > 0)

  and (.diagnostics.sourceEligibilityMatrix.sms == "FS-940-HDS-010-SDS-020-SMS-030")
  and (.diagnostics.sourceEligibilityMatrix.groupedOncePerSite == true)
  and (.diagnostics.sourceEligibilityMatrix.remoteGroupCount == .diagnostics.nextHopIdentities)
  and (.diagnostics.sourceEligibilityMatrix.eligiblePairCount > .diagnostics.routeAtomIndex.atomCount)
  and (.diagnostics.sourceEligibilityMatrix.rejectedPairCount > 0)
  and (.diagnostics.sourceEligibilityMatrix.keyFields == [
    "sourceNode",
    "routeAtomId",
    "owner",
    "kind",
    "overlay",
    "uplink",
    "access",
    "serviceName"
  ])

  and (.diagnostics.nextHopEquivalence.sms == "FS-940-HDS-010-SDS-020-SMS-040")
  and (.diagnostics.nextHopEquivalence.resolvedOncePerDistinctTuple == true)
  and ((.diagnostics.nextHopEquivalence.entries | length) == .diagnostics.forwardingEquivalenceKeys)
  and all(.diagnostics.nextHopEquivalence.entries[];
    ((.sourceNode // null) != null)
    and ((.destinationOwner // null) != null)
    and ((.routeKind // null) != null)
    and ((.hopNode // null) != null)
    and ((.linkName // null) != null)
    and (((.via4 // null) != null) or ((.via6 // null) != null))
    and ((.routeIntentClass // null) != null)
    and ((.routeAtomIds // []) | length > 0)
  )

  and (.diagnostics.forwardingEquivalencePlanner.sms == "FS-940-HDS-010-SDS-020-SMS-050")
  and (.diagnostics.forwardingEquivalencePlanner.source == "route-atom-index-and-next-hop-equivalence")
  and (.diagnostics.forwardingEquivalencePlanner.routeRows == .diagnostics.forwardingEquivalenceKeys)
  and (.diagnostics.forwardingEquivalencePlanner.preservesSelectedScopes == true)

  and (.diagnostics.routeExceptionLayer.sms == "FS-940-HDS-010-SDS-020-SMS-060")
  and (.diagnostics.routeExceptionLayer.source == "after-forwarding-equivalence-groups")
  and (.diagnostics.routeExceptionLayer.mutatesCommonGroups == false)
  and (.diagnostics.routeExceptionLayer.p2pExactGroups > 0)
  and (.diagnostics.routeExceptionLayer.selectedScopeGroups > 0)

  and (.diagnostics.materializer.sms == "FS-940-HDS-010-SDS-020-SMS-070")
  and (.diagnostics.materializer.source == "finished-site-plan")
  and (.diagnostics.materializer.perInterfaceNormalizationAuthoritative == false)
  and (.diagnostics.materializer.routeRows == .diagnostics.forwardingEquivalenceKeys)
  and (.diagnostics.usesExistingPerNodeExpansion == false)

  and (.diagnostics.routeCardinalityEquivalence.sms == "FS-940-HDS-010-SDS-020-SMS-080")
  and (.diagnostics.routeCardinalityEquivalence.hasEquivalenceKeys == true)
  and (.diagnostics.routeCardinalityEquivalence.provesBeforePromotion == true)
  and (.diagnostics.routeCardinalityEquivalence.finalMaterializedRouteCount == .diagnostics.finalMaterializedRouteCount)
  and (.diagnostics.routeCardinalityEquivalence.routeAtomCount >= .diagnostics.routeAtomIndex.atomCount)
' <<<"${contract_json}" >/dev/null || {
  echo "${contract_json}" >&2
  fail "route planner child atom diagnostics do not satisfy SMS-020 through SMS-080"
}

pass_timed "fs940-route-planner-child-atoms"
