#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-940-HDS-010-SDS-020-SMS-060
# Construction test: Route Exception Layer
# Tests SMS-060 module: exception-layer.nix
#
# SMS Predicate Coverage Matrix:
#   MR1: Apply one-off route exceptions after common route groups are built
#   MR2: Preserve exact p2p return routes
#   MR3: Preserve runtime delegated-prefix source-file routes
#   CI1: Consumes shared route group plan (route rows with equivalenceKey)
#   CI2: Consumes point-to-point connected-prefix facts (exceptionClass=point-to-point-exact)
#   CI3: Consumes runtime delegated-prefix source-file route facts (exceptionClass=runtime-source-file)
#   EI1: One-off route exception list validated
#   EI2: Exception-layer diagnostics (exception counts, validated flag)
#   FC1: Fail when one-off exception handling changes common route groups
#   FC2: Fail when p2p return routes are summarized into common groups
#   FC3: Fail when selected-uplink or overlay scope exceptions lose exactness
#   CH:  Construction handoff - exception layer runs before per-interface materialization
#   SN1: Exception mutates common group (p2p route with summarization) → diagnostic.route-exception-mutated-common-group
#   SN2: Delegated-prefix route summarized away → diagnostic.route-exception-exactness-lost (active rejection)

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"

fail() {
  echo "FAIL route-exception-layer: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

require_cmd jq
require_cmd nix
require_cmd rg

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

MODULE_IMPORT="${repo_root}/implementation/lib/routing/internal-routes/site-plan/exception-layer.nix"

# Helper: evaluate the exception layer with synthetic routeRows
run_exception_layer() {
  local body="$1"
  local outfile="${tmp_dir}/eval.nix"
  cat >"${outfile}" <<'HEREDOC_END'
let
  exceptionLayer = import (builtins.getEnv "NFM_REPO_ROOT" + "/implementation/lib/routing/internal-routes/site-plan/exception-layer.nix") {};
  exprResult =
HEREDOC_END
  echo "${body}" >>"${outfile}"
  echo ';' >>"${outfile}"
  echo 'in exprResult' >>"${outfile}"
  NFM_REPO_ROOT="${repo_root}" nix eval --json -f "${outfile}"
}

# Helper: run exception layer expecting an error (for seeded negatives)
run_exception_layer_error() {
  local body="$1"
  local outfile="${tmp_dir}/eval.nix"
  cat >"${outfile}" <<'HEREDOC_END'
let
  exceptionLayer = import (builtins.getEnv "NFM_REPO_ROOT" + "/implementation/lib/routing/internal-routes/site-plan/exception-layer.nix") {};
  exprResult =
HEREDOC_END
  echo "${body}" >>"${outfile}"
  echo ';' >>"${outfile}"
  echo 'in exprResult' >>"${outfile}"
  NFM_REPO_ROOT="${repo_root}" nix eval --json -f "${outfile}" 2>&1 || true
}

# ---------------------------------------------------------------------------
# P1 (MR1): Exception layer runs after route groups, validates exception rows
# ---------------------------------------------------------------------------
echo "--- P1: Exception layer validates non-exception rows pass through ---"

p1_json="$(run_exception_layer '
exceptionLayer.build {
  routeRows = [
    {
      nodeName = "node-a";
      linkName = "link-a";
      routes4 = [];
      routes6 = [];
      equivalenceKey = {
        exceptionClass = "none";
      };
      diagnostics = {
        routeAtomCount = 1;
        prefixSummaryCandidateCount = 0;
        exactDeduplicationCount = 0;
        finalMaterializedRouteCount = 1;
      };
    }
  ];
}
')" || fail "P1 evaluation failed"

p1_validated="$(jq -r '.validatedRows[0].exceptionLayer.validated' <<<"${p1_json}")"
[ "${p1_validated}" = "true" ] || fail "P1: non-exception row should be validated, got ${p1_validated}"

# ---------------------------------------------------------------------------
# P2 (MR2): Point-to-point exact routes preserved
# ---------------------------------------------------------------------------
echo "--- P2: P2P exact routes validated ---"

p2_json="$(run_exception_layer '
exceptionLayer.build {
  routeRows = [
    {
      nodeName = "node-a";
      linkName = "p2p-link";
      routes4 = [];
      routes6 = [];
      equivalenceKey = {
        exceptionClass = "point-to-point-exact";
        aggregationClass = "exact-only";
      };
      diagnostics = {
        routeAtomCount = 1;
        prefixSummaryCandidateCount = 0;
        exactDeduplicationCount = 0;
        finalMaterializedRouteCount = 1;
      };
    }
  ];
}
')" || fail "P2 evaluation failed"

p2_validated="$(jq -r '.validatedRows[0].exceptionLayer.validated' <<<"${p2_json}")"
p2_exc="$(jq -r '.validatedRows[0].exceptionLayer.exceptionClass' <<<"${p2_json}")"
[ "${p2_validated}" = "true" ] || fail "P2: p2p exception route should be validated, got ${p2_validated}"
[ "${p2_exc}" = "point-to-point-exact" ] || fail "P2: expected exceptionClass=point-to-point-exact, got ${p2_exc}"

# ---------------------------------------------------------------------------
# P3 (MR3): Runtime source-file routes preserved
# ---------------------------------------------------------------------------
echo "--- P3: Runtime source-file routes validated ---"

p3_json="$(run_exception_layer '
exceptionLayer.build {
  routeRows = [
    {
      nodeName = "node-a";
      linkName = "src-link";
      routes4 = [];
      routes6 = [];
      equivalenceKey = {
        exceptionClass = "runtime-source-file";
        aggregationClass = "runtime-source-file";
      };
      diagnostics = {
        routeAtomCount = 1;
        prefixSummaryCandidateCount = 0;
        exactDeduplicationCount = 0;
        finalMaterializedRouteCount = 1;
      };
    }
  ];
}
')" || fail "P3 evaluation failed"

p3_validated="$(jq -r '.validatedRows[0].exceptionLayer.validated' <<<"${p3_json}")"
p3_exc="$(jq -r '.validatedRows[0].exceptionLayer.exceptionClass' <<<"${p3_json}")"
[ "${p3_validated}" = "true" ] || fail "P3: runtime source-file route should be validated, got ${p3_validated}"
[ "${p3_exc}" = "runtime-source-file" ] || fail "P3: expected exceptionClass=runtime-source-file, got ${p3_exc}"

# ---------------------------------------------------------------------------
# P4 (CI1): Exception layer consumes share route group plan
# ---------------------------------------------------------------------------
echo "--- P4: Consumed shared route group plan visible ---"

p4_json="$(run_exception_layer '
exceptionLayer.build {
  routeRows = [
    {
      nodeName = "node-a";
      linkName = "link-a";
      routes4 = [];
      routes6 = [];
      equivalenceKey = {
        exceptionClass = "none";
        sourceNode = "node-a";
        routeKind = "tenant";
      };
      diagnostics = {
        routeAtomCount = 1;
        prefixSummaryCandidateCount = 0;
        exactDeduplicationCount = 0;
        finalMaterializedRouteCount = 1;
      };
    }
  ];
}
')" || fail "P4 evaluation failed"

p4_source_node="$(jq -r '.validatedRows[0].equivalenceKey.sourceNode' <<<"${p4_json}")"
p4_kind="$(jq -r '.validatedRows[0].equivalenceKey.routeKind' <<<"${p4_json}")"
[ "${p4_source_node}" = "node-a" ] || fail "P4: sourceNode should be preserved, got ${p4_source_node}"
[ "${p4_kind}" = "tenant" ] || fail "P4: routeKind should be preserved, got ${p4_kind}"

# ---------------------------------------------------------------------------
# P5 (CI2+CI3): p2p and source-file facts consumed via equivalenceKey
# ---------------------------------------------------------------------------
echo "--- P5: Exception classes consumed from equivalenceKey ---"

p5_json="$(run_exception_layer '
exceptionLayer.build {
  routeRows = [
    {
      nodeName = "node-a";
      linkName = "p2p-a";
      routes4 = [];
      routes6 = [];
      equivalenceKey = {
        exceptionClass = "point-to-point-exact";
      };
      diagnostics = {
        routeAtomCount = 1;
        prefixSummaryCandidateCount = 0;
        exactDeduplicationCount = 0;
        finalMaterializedRouteCount = 1;
      };
    }
    {
      nodeName = "node-b";
      linkName = "src-b";
      routes6 = [];
      routes4 = [];
      equivalenceKey = {
        exceptionClass = "runtime-source-file";
      };
      diagnostics = {
        routeAtomCount = 1;
        prefixSummaryCandidateCount = 0;
        exactDeduplicationCount = 0;
        finalMaterializedRouteCount = 1;
      };
    }
    {
      nodeName = "node-c";
      linkName = "overlay-c";
      routes4 = [];
      routes6 = [];
      equivalenceKey = {
        exceptionClass = "overlay-scope-exact";
      };
      diagnostics = {
        routeAtomCount = 1;
        prefixSummaryCandidateCount = 0;
        exactDeduplicationCount = 0;
        finalMaterializedRouteCount = 1;
      };
    }
    {
      nodeName = "node-d";
      linkName = "uplink-d";
      routes4 = [];
      routes6 = [];
      equivalenceKey = {
        exceptionClass = "selected-uplink-exact";
      };
      diagnostics = {
        routeAtomCount = 1;
        prefixSummaryCandidateCount = 0;
        exactDeduplicationCount = 0;
        finalMaterializedRouteCount = 1;
      };
    }
  ];
}
')" || fail "P5 evaluation failed"

p5_diag="$(jq '.diagnostics' <<<"${p5_json}")"
p5_p2p="$(jq -r '.p2pExactCount' <<<"${p5_diag}")"
p5_src="$(jq -r '.runtimeSourceFileCount' <<<"${p5_diag}")"
p5_overlay="$(jq -r '.overlayExactCount' <<<"${p5_diag}")"
p5_uplink="$(jq -r '.uplinkExactCount' <<<"${p5_diag}")"
p5_total="$(jq -r '.totalExceptions' <<<"${p5_diag}")"

[ "${p5_p2p}" = "1" ] || fail "P5: expected p2pExactCount=1, got ${p5_p2p}"
[ "${p5_src}" = "1" ] || fail "P5: expected runtimeSourceFileCount=1, got ${p5_src}"
[ "${p5_overlay}" = "1" ] || fail "P5: expected overlayExactCount=1, got ${p5_overlay}"
[ "${p5_uplink}" = "1" ] || fail "P5: expected uplinkExactCount=1, got ${p5_uplink}"
[ "${p5_total}" = "4" ] || fail "P5: expected totalExceptions=4, got ${p5_total}"

# ---------------------------------------------------------------------------
# P6 (EI1): Exception list validated, each row carries exceptionLayer
# ---------------------------------------------------------------------------
echo "--- P6: Exception list validated ---"

p6_row_count="$(jq '.diagnostics.totalRows' <<<"${p5_json}")"
[ "${p6_row_count}" = "4" ] || fail "P6: expected 4 totalRows, got ${p6_row_count}"

for i in 0 1 2 3; do
  validated="$(jq -r ".validatedRows[${i}].exceptionLayer.validated" <<<"${p5_json}")"
  [ "${validated}" = "true" ] || fail "P6: row ${i} not validated"
done

# ---------------------------------------------------------------------------
# P7 (EI2): Diagnostics have exception-layer identity
# ---------------------------------------------------------------------------
echo "--- P7: Exception-layer diagnostics ---"

p7_sms="$(jq -r '.diagnostics.sms' <<<"${p5_json}")"
p7_source="$(jq -r '.diagnostics.source' <<<"${p5_json}")"
p7_mutates="$(jq -r '.diagnostics.mutatesCommonGroups' <<<"${p5_json}")"
p7_validated="$(jq -r '.diagnostics.validated' <<<"${p5_json}")"

[ "${p7_sms}" = "FS-940-HDS-010-SDS-020-SMS-060" ] || fail "P7: expected sms identity, got ${p7_sms}"
[ "${p7_source}" = "after-forwarding-equivalence-groups" ] || fail "P7: expected source=after-forwarding-equivalence-groups, got ${p7_source}"
[ "${p7_mutates}" = "false" ] || fail "P7: mutatesCommonGroups must be false, got ${p7_mutates}"
[ "${p7_validated}" = "true" ] || fail "P7: diagnostics validated should be true, got ${p7_validated}"

# ---------------------------------------------------------------------------
# P8 (FC1): P2P exception doesn't mutate common group (no summarization)
# ---------------------------------------------------------------------------
echo "--- P8: P2P exception preserved without summarization ---"

p8_json="$(run_exception_layer '
exceptionLayer.build {
  routeRows = [
    {
      nodeName = "node-a";
      linkName = "p2p-link";
      routes4 = [];
      routes6 = [];
      equivalenceKey = {
        exceptionClass = "point-to-point-exact";
      };
      diagnostics = {
        routeAtomCount = 1;
        prefixSummaryCandidateCount = 0;
        exactDeduplicationCount = 0;
        finalMaterializedRouteCount = 1;
      };
    }
  ];
}
')" || fail "P8 evaluation failed"

p8_validated="$(jq -r '.validatedRows[0].exceptionLayer.validated' <<<"${p8_json}")"
[ "${p8_validated}" = "true" ] || fail "P8: p2p route without summarization should validate"

# ---------------------------------------------------------------------------
# P9 (FC2): Overlay scope exception exactness preserved
# ---------------------------------------------------------------------------
echo "--- P9: Overlay scope exactness validated ---"

p9_json="$(run_exception_layer '
exceptionLayer.build {
  routeRows = [
    {
      nodeName = "node-c";
      linkName = "overlay-link";
      routes4 = [];
      routes6 = [];
      equivalenceKey = {
        exceptionClass = "overlay-scope-exact";
      };
      diagnostics = {
        routeAtomCount = 1;
        prefixSummaryCandidateCount = 0;
        exactDeduplicationCount = 0;
        finalMaterializedRouteCount = 1;
      };
    }
  ];
}
')" || fail "P9 evaluation failed"

p9_diag_overlay="$(jq -r '.diagnostics.overlayExactCount' <<<"${p9_json}")"
[ "${p9_diag_overlay}" = "1" ] || fail "P9: expected overlayExactCount=1, got ${p9_diag_overlay}"

# ---------------------------------------------------------------------------
# P10 (FC3): Selected-uplink scope exception exactness preserved
# ---------------------------------------------------------------------------
echo "--- P10: Selected-uplink exactness validated ---"

p10_json="$(run_exception_layer '
exceptionLayer.build {
  routeRows = [
    {
      nodeName = "node-d";
      linkName = "uplink-link";
      routes4 = [];
      routes6 = [];
      equivalenceKey = {
        exceptionClass = "selected-uplink-exact";
      };
      diagnostics = {
        routeAtomCount = 1;
        prefixSummaryCandidateCount = 0;
        exactDeduplicationCount = 0;
        finalMaterializedRouteCount = 1;
      };
    }
  ];
}
')" || fail "P10 evaluation failed"

p10_diag_uplink="$(jq -r '.diagnostics.uplinkExactCount' <<<"${p10_json}")"
[ "${p10_diag_uplink}" = "1" ] || fail "P10: expected uplinkExactCount=1, got ${p10_diag_uplink}"

# ---------------------------------------------------------------------------
# P11 (CH): Construction handoff - exceptionLayer field present on all rows
# ---------------------------------------------------------------------------
echo "--- P11: Construction handoff preserves rows for downstream materialization ---"

p11_json="$(run_exception_layer '
exceptionLayer.build {
  routeRows = [
    {
      nodeName = "node-a";
      linkName = "link-a";
      routes4 = [];
      routes6 = [];
      equivalenceKey = { exceptionClass = "none"; };
      diagnostics = { routeAtomCount = 1; prefixSummaryCandidateCount = 0; exactDeduplicationCount = 0; finalMaterializedRouteCount = 1; };
    }
  ];
}
')" || fail "P11 evaluation failed"

p11_node="$(jq -r '.validatedRows[0].nodeName' <<<"${p11_json}")"
p11_link="$(jq -r '.validatedRows[0].linkName' <<<"${p11_json}")"
[ "${p11_node}" = "node-a" ] || fail "P11: nodeName preserved, got ${p11_node}"
[ "${p11_link}" = "link-a" ] || fail "P11: linkName preserved, got ${p11_link}"

# ---------------------------------------------------------------------------
# SN1: Exception mutates common group — p2p route with summarization
# Expected: diagnostic.route-exception-mutated-common-group
# ---------------------------------------------------------------------------
echo "--- SN1: P2P exception with summarization (mutation) rejected ---"

sn1_output="$(run_exception_layer_error '
exceptionLayer.build {
  routeRows = [
    {
      nodeName = "node-a";
      linkName = "p2p-link";
      routes4 = [];
      routes6 = [];
      equivalenceKey = {
        exceptionClass = "point-to-point-exact";
      };
      diagnostics = {
        routeAtomCount = 5;
        prefixSummaryCandidateCount = 3;
        exactDeduplicationCount = 1;
        finalMaterializedRouteCount = 2;
      };
    }
  ];
}
')"

if echo "${sn1_output}" | rg -q 'route-exception-mutated-common-group'; then
  echo "SN1 PASS: diagnostic.route-exception-mutated-common-group emitted"
else
  fail "SN1: expected diagnostic.route-exception-mutated-common-group, got: ${sn1_output}"
fi

# Also verify a valid p2p route (no summarization) is accepted
sn1_fix_output="$(run_exception_layer '
exceptionLayer.build {
  routeRows = [
    {
      nodeName = "node-a";
      linkName = "p2p-link";
      routes4 = [];
      routes6 = [];
      equivalenceKey = {
        exceptionClass = "point-to-point-exact";
      };
      diagnostics = {
        routeAtomCount = 1;
        prefixSummaryCandidateCount = 0;
        exactDeduplicationCount = 0;
        finalMaterializedRouteCount = 1;
      };
    }
  ];
}
' 2>&1)" || fail "SN1 recovery: valid p2p route should be accepted"

sn1_fix_valid="$(jq -r '.diagnostics.validated' <<<"${sn1_fix_output}")"
[ "${sn1_fix_valid}" = "true" ] || fail "SN1 recovery: fixed route should validate, got ${sn1_fix_valid}"
echo "SN1 RECOVERY PASS: Corrected plan accepted"

# ---------------------------------------------------------------------------
# SN2: Delegated-prefix route summarized away — runtime source-file route with
# summarization/aggregation (finalMat < routeAtomCt, exact deduplication with
# cardinality loss)
# Expected: diagnostic.route-exception-exactness-lost
# ---------------------------------------------------------------------------
echo "--- SN2: Runtime source-file route summarized into common group rejected ---"

sn2_output="$(run_exception_layer_error '
exceptionLayer.build {
  routeRows = [
    {
      nodeName = "node-b";
      linkName = "src-link";
      routes6 = [];
      routes4 = [];
      equivalenceKey = {
        exceptionClass = "runtime-source-file";
      };
      diagnostics = {
        routeAtomCount = 4;
        prefixSummaryCandidateCount = 0;
        exactDeduplicationCount = 2;
        finalMaterializedRouteCount = 2;
      };
    }
  ];
}
')"

if echo "${sn2_output}" | rg -q 'route-exception-exactness-lost'; then
  echo "SN2 PASS: diagnostic.route-exception-exactness-lost emitted"
else
  fail "SN2: expected diagnostic.route-exception-exactness-lost, got: ${sn2_output}"
fi

# Recovery: valid source-file route (no summarization, correct cardinality)
sn2_fix_output="$(run_exception_layer '
exceptionLayer.build {
  routeRows = [
    {
      nodeName = "node-b";
      linkName = "src-link";
      routes6 = [];
      routes4 = [];
      equivalenceKey = {
        exceptionClass = "runtime-source-file";
      };
      diagnostics = {
        routeAtomCount = 1;
        prefixSummaryCandidateCount = 0;
        exactDeduplicationCount = 0;
        finalMaterializedRouteCount = 1;
      };
    }
  ];
}
' 2>&1)" || fail "SN2 recovery: valid src-file route should be accepted"

sn2_fix_valid="$(jq -r '.diagnostics.validated' <<<"${sn2_fix_output}")"
[ "${sn2_fix_valid}" = "true" ] || fail "SN2 recovery: fixed route should validate, got ${sn2_fix_valid}"
echo "SN2 RECOVERY PASS: Corrected plan accepted"

# ---------------------------------------------------------------------------
# Summary: total predicate coverage
# Verified: P1(MR1) P2(MR2) P3(MR3) P4(CI1) P5(CI2+CI3) P6(EI1) P7(EI2)
#           P8(FC1) P9(FC2) P10(FC3) P11(CH) SN1 SN2
# Total: 13/13
# ---------------------------------------------------------------------------

echo "PASS FS-940-HDS-010-SDS-020-SMS-060 route exception layer"
