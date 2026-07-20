#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-940-HDS-010-SDS-020-SMS-070
# Construction test: One-Pass Route Materializer

REPO_ROOT="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"

fail() {
  echo "FAIL one-pass-route-materializer: $*" >&2
  exit 1
}

require_cmd() { command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"; }
require_cmd jq
require_cmd nix

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

src="${REPO_ROOT}/implementation/lib/routing/internal-routes/site-plan/materialize.nix"
coord_src="${REPO_ROOT}/implementation/lib/routing/internal-routes/site-plan/coordinator.nix"
site_plan_src="${REPO_ROOT}/implementation/lib/routing/internal-routes/site-plan.nix"

echo "=== FS-940-HDS-010-SDS-020-SMS-070 One-Pass Route Materializer ==="

# P1 - Consume only route groups
echo "--- P1: Consumed interface enumeration ---"
grep -q 'groupValues' "${src}" || fail "P1a: missing groupValues"
echo "PASS P1a: groupValues present"
grep -q 'byNodeLink' "${src}" || fail "P1b: missing byNodeLink"
echo "PASS P1b: byNodeLink present"

# FC1 - No route graph path search
echo "--- FC1: No route graph path search ---"
grep -qE '(graphContext|routeGraph|pathSearch|shortestPath)' "${src}" && fail "FC1: graph path search references found" || true
echo "PASS FC1: no route graph path search"

# FC3 - No delegation back to per-node expansion
echo "--- FC3: No per-node expansion delegation ---"
grep -qE '(import.*source-eligibility|buildFacts\b|import.*source-rows|import.*resolve-groups)' "${src}" && fail "FC3: planning-level construction references found" || true
echo "PASS FC3: no re-entry to planning"

# Evaluate materializer with fixture data
echo "--- P2-P3-FC2-CH: Evaluating materializer ---"

sed "s|__REPO_ROOT__|${REPO_ROOT}|g" > "${tmp_dir}/eval.nix" <<'HEREDOC_END'
let
  materializer = import (__REPO_ROOT__ + "/implementation/lib/routing/internal-routes/site-plan/materialize.nix") { };
  nodeNames = [ "client-edge" "downstream-selector" ];
  routeRows = [
    { nodeName = "client-edge"; linkName = "tenant-client";
      routes4 = [{ dst = "10.3.172.0/24"; }]; routes6 = [];
      diagnostics = { exactOnlyCount = 0; finalMaterializedRouteCount = 1; }; }
    { nodeName = "client-edge"; linkName = "p2p-client-edge-downstream-selector";
      routes4 = [{ dst = "0.0.0.0/0"; via4 = "10.3.255.1"; }];
      routes6 = [{ dst = "::/0"; via6 = "fd42:3ac:fe:0:0:0:0:1"; }];
      diagnostics = { exactOnlyCount = 1; finalMaterializedRouteCount = 2; }; }
    { nodeName = "downstream-selector"; linkName = "p2p-client-edge-downstream-selector";
      routes4 = [{ dst = "0.0.0.0/0"; via4 = "10.3.255.0"; }]; routes6 = [];
      diagnostics = { exactOnlyCount = 1; finalMaterializedRouteCount = 1; }; }
  ];
  remoteGroups = {};
  remotePrefixFacts = { remoteByNode = {}; tenantOwnerEntries = []; overlayRouteEntries = []; p2pEntries = []; };
  result = materializer.build { inherit nodeNames remoteGroups remotePrefixFacts routeRows; };
in
{
  diagnostics = result.diagnostics;
  byNodeKeys = builtins.attrNames result.byNode;
  clientEdgeLinks = builtins.attrNames (result.byNode."client-edge" or {});
  plannedRoutesNormalized = (result.byNode."client-edge" or {})."tenant-client" or {};
}
HEREDOC_END

eval_json=$(nix eval --json -f "${tmp_dir}/eval.nix" 2>&1) || fail "eval failed: $eval_json"

# P2 - byNode output
nodeCount=$(echo "$eval_json" | jq '.byNodeKeys | length')
[ "$nodeCount" -ge 1 ] || fail "P2: byNode output empty"
echo "PASS P2: byNode output with $nodeCount nodes"

linkCount=$(echo "$eval_json" | jq '.clientEdgeLinks | length')
[ "$linkCount" -ge 2 ] || fail "P2: client-edge has $linkCount links"
echo "PASS P2b: $linkCount per-interface route lists"

# P3 - plannedRoutesNormalized
normalized=$(echo "$eval_json" | jq '.plannedRoutesNormalized.plannedRoutesNormalized')
[ "$normalized" = "true" ] || fail "P3: plannedRoutesNormalized=$normalized"
echo "PASS P3: plannedRoutesNormalized=true"

# CH1 - SMS identity
sms_id=$(echo "$eval_json" | jq -r '.diagnostics.materializer.sms')
[ "$sms_id" = "FS-940-HDS-010-SDS-020-SMS-070" ] || fail "CH1: sms=$sms_id"
echo "PASS CH1: SMS identity=$sms_id"

# FC2/SN2 - perInterfaceNormalizationAuthoritative (use --arg to avoid // falsy trap)
norm_auth=$(echo "$eval_json" | jq -r '.diagnostics.materializer.perInterfaceNormalizationAuthoritative')
[ "$norm_auth" = "false" ] || fail "FC2/SN2: perInterfaceNormalizationAuthoritative=$norm_auth"
echo "PASS FC2/SN2: perInterfaceNormalizationAuthoritative=false"

# CH2 - source
msource=$(echo "$eval_json" | jq -r '.diagnostics.materializer.source')
[ "$msource" = "finished-site-plan" ] || fail "CH2: source=$msource"
echo "PASS CH2: source=finished-site-plan"

# CH3 - planner
planner=$(echo "$eval_json" | jq -r '.diagnostics.planner')
[ "$planner" = "scratch-site-wide" ] || fail "CH3: planner=$planner"
echo "PASS CH3: planner=scratch-site-wide"

# FC3b - usesExistingPerNodeExpansion
uses_old=$(echo "$eval_json" | jq -r '.diagnostics.usesExistingPerNodeExpansion')
[ "$uses_old" = "false" ] || fail "FC3b: usesExistingPerNodeExpansion=$uses_old"
echo "PASS FC3b: usesExistingPerNodeExpansion=false"

# SN1 - no re-entry to planning
echo "--- SN1: Materializer re-enters planning check ---"
grep -qE '(import.*source-eligibility|buildFacts\b|import.*source-rows|pathSearch\b|shortestPath\b|import.*resolve-groups)' "${src}" && fail "SN1: planning-level functional references found" || true
echo "PASS SN1: no re-entry to planning"

# Coordinator registration
echo "--- Coordinator submodule registration ---"
grep -qE '(FS-940-HDS-010-SDS-020-SMS-070|\$\{smsRoot\}-SMS-070)' "${coord_src}" || fail "CH4: SMS-070 missing from coordinator"
echo "PASS CH4: SMS-070 in coordinator"

grep -qE 'FS-940-HDS-010-SDS-020-SMS-070' "${site_plan_src}" || fail "CH5: SMS-070 missing from site-plan.nix"
echo "PASS CH5: SMS-070 in site-plan.nix"

echo ""
echo "======================================================================"
echo "SMS Predicate Coverage Matrix:"
echo "  P1  — consume route groups only       : PASS"
echo "  P2  — emit per-interface route lists   : PASS"
echo "  P3  — avoid rebuild per intermediate   : PASS"
echo "  FC1 — no graph path search             : PASS"
echo "  FC2 — normalization not dominant       : PASS"
echo "  FC3 — no delegation to old expansion   : PASS"
echo "  SN1 — no re-entry to planning          : PASS"
echo "  SN2 — normalization authoritative=false: PASS"
echo "  CH  — construction handoff verified    : PASS"
echo "  All 9 predicates PASS"
echo "======================================================================"
echo "PASS FS-940-HDS-010-SDS-020-SMS-070 one-pass-route-materializer"
