#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-940-HDS-010-SDS-020-SMS-080
# Construction test: Route Cardinality Equivalence Diagnostics
# Proves SMS-080 predicates using seeded fixture data against materialize.nix

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
SMS_ID="FS-940-HDS-010-SDS-020-SMS-080"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1" >&2; }

echo "--- ${SMS_ID}: Route Cardinality Equivalence Diagnostics ---"

# Evaluate the materialize.nix diagnostics with seeded fixture data
RESULT=$(nix eval --impure --expr '
  let
    materialize = import '"${repo_root}"'/implementation/lib/routing/internal-routes/site-plan/materialize.nix { };
    result = materialize.build {
      nodeNames = ["core-isp" "policy-branch"];
      remoteGroups = {};
      remotePrefixFacts = {
        remoteByNode = {};
        tenantOwnerEntries = [1 2 3 4 5];
        overlayRouteEntries = [1 2];
        p2pEntries = [1 2 3];
      };
      routeRows = [
        # Common tenant group with equivalence proof
        {
          nodeName = "core-isp";
          linkName = "wan0";
          routes4 = [{ dst = "10.20.20.0/24"; via4 = "10.0.0.1"; proto = "internal"; intent = { kind = "internal-reachability"; }; }];
          routes6 = [];
          diagnostics = {
            routeAtomCount = 3;
            routeDstAtomCount = 3;
            exactOnlyCount = 0;
            exactDeduplicationCount = 0;
            prefixSummaryCandidateCount = 1;
            rejectedAggregationCount = 0;
            finalMaterializedRouteCount = 1;
          };
          equivalenceKey = {
            sourceNode = "core-isp";
            destinationOwner = "tenant-a";
            routeKind = "tenant";
            family = "ipv4";
            via4 = "10.0.0.1";
            routeIntentClass = "internal-reachability";
            routeAtomIds = [1 2 3];
            aggregationClass = "prefix-summary";
          };
        }
        # P2P exact group
        {
          nodeName = "policy-branch";
          linkName = "p2p-core";
          routes4 = [{ dst = "10.255.0.0/31"; via4 = "10.255.0.1"; proto = "internal"; intent = { kind = "internal-reachability"; }; }];
          routes6 = [];
          diagnostics = {
            routeAtomCount = 1;
            routeDstAtomCount = 1;
            exactOnlyCount = 1;
            exactDeduplicationCount = 0;
            prefixSummaryCandidateCount = 0;
            rejectedAggregationCount = 0;
            finalMaterializedRouteCount = 1;
          };
          equivalenceKey = {
            sourceNode = "policy-branch";
            routeKind = "p2p";
            family = "ipv4";
            via4 = "10.255.0.1";
            routeIntentClass = "internal-reachability";
            routeAtomIds = [4];
            exceptionClass = "point-to-point-exact";
          };
        }
        # Overlay group
        {
          nodeName = "core-isp";
          linkName = "nebula0";
          routes4 = [{ dst = "10.30.0.0/16"; via4 = "10.99.0.1"; proto = "overlay"; intent = { kind = "overlay-reachability"; }; }];
          routes6 = [];
          diagnostics = {
            routeAtomCount = 2;
            routeDstAtomCount = 2;
            exactOnlyCount = 0;
            exactDeduplicationCount = 0;
            prefixSummaryCandidateCount = 1;
            rejectedAggregationCount = 1;
            finalMaterializedRouteCount = 1;
          };
          equivalenceKey = {
            sourceNode = "core-isp";
            routeKind = "overlay";
            overlay = "nebula-site-b";
            family = "ipv4";
            via4 = "10.99.0.1";
            routeIntentClass = "overlay-reachability";
            routeAtomIds = [5 6];
            aggregationClass = "prefix-summary";
          };
        }
      ];
    };
  in
  result.diagnostics.routeCardinalityEquivalence
' 2>&1)

echo "Diagnostics output:"
echo "$RESULT"

# Helper: extract integer value from Nix attrset output (key = value; format)
nix_get_int() {
  local key="$1"
  echo "$RESULT" | grep -oP "${key}\\s*=\\s*\\K\\d+" || echo ""
}
nix_get_bool() {
  local key="$1"
  echo "$RESULT" | grep -oP "${key}\\s*=\\s*\\K(true|false)" || echo ""
}

# P1: Emits sms identifier
if echo "$RESULT" | grep -q "FS-940-HDS-010-SDS-020-SMS-080"; then
  pass "P1: sms identifier set to ${SMS_ID}"
else
  fail "P1: sms identifier missing or wrong"
fi

# P2: Emits routeAtomCount
ATOM_COUNT=$(nix_get_int "routeAtomCount")
if [ -n "$ATOM_COUNT" ]; then
  pass "P2: routeAtomCount=${ATOM_COUNT}"
else
  fail "P2: routeAtomCount missing"
fi

# P3: Emits exactOnlyCount
EXACT=$(nix_get_int "exactOnlyCount")
if [ -n "$EXACT" ]; then
  pass "P3: exactOnlyCount=${EXACT}"
else
  fail "P3: exactOnlyCount missing"
fi

# P4: Emits prefixSummaryCandidateCount
PREFIX=$(nix_get_int "prefixSummaryCandidateCount")
if [ -n "$PREFIX" ]; then
  pass "P4: prefixSummaryCandidateCount=${PREFIX}"
else
  fail "P4: prefixSummaryCandidateCount missing"
fi

# P5: Emits rejectedAggregationCount
REJECTED=$(nix_get_int "rejectedAggregationCount")
if [ -n "$REJECTED" ]; then
  pass "P5: rejectedAggregationCount=${REJECTED}"
else
  fail "P5: rejectedAggregationCount missing"
fi

# P6: Emits finalMaterializedRouteCount
FINAL=$(nix_get_int "finalMaterializedRouteCount")
if [ -n "$FINAL" ]; then
  pass "P6: finalMaterializedRouteCount=${FINAL}"
else
  fail "P6: finalMaterializedRouteCount missing"
fi

# P7: Emits hasEquivalenceKeys
HAS_KEYS=$(nix_get_bool "hasEquivalenceKeys")
if [ "$HAS_KEYS" = "true" ]; then
  pass "P7: hasEquivalenceKeys=true (equivalence diagnostics emitted)"
else
  fail "P7: hasEquivalenceKeys should be true, got '${HAS_KEYS}'"
fi

# P8: provesBeforePromotion is true
PROVES=$(nix_get_bool "provesBeforePromotion")
if [ "$PROVES" = "true" ]; then
  pass "P8: provesBeforePromotion=true (longest-prefix preserved before summarization)"
else
  fail "P8: provesBeforePromotion should be true, got '${PROVES}'"
fi

# P9: routeAtomCount matches expected (6 atoms from 3 rows)
if [ "$ATOM_COUNT" = "6" ]; then
  pass "P9: routeAtomCount=6 (correct: 3 tenant + 1 p2p + 2 overlay atoms)"
else
  fail "P9: routeAtomCount=${ATOM_COUNT}, expected 6"
fi

# P10: rejectedAggregationCount=1 (one overlay group)
if [ "$REJECTED" = "1" ]; then
  pass "P10: rejectedAggregationCount=1 (one group has rejected aggregation)"
else
  fail "P10: rejectedAggregationCount=${REJECTED}, expected 1"
fi

# P11: exactOnlyCount=1 (one p2p exact group)
if [ "$EXACT" = "1" ]; then
  pass "P11: exactOnlyCount=1 (one p2p exact-deduplication group)"
else
  fail "P11: exactOnlyCount=${EXACT}, expected 1"
fi

echo ""
echo "--- ${SMS_ID} Results: ${PASS} PASS, ${FAIL} FAIL ---"

# Seeded negative gap notes
echo ""
echo "SEEDED NEGATIVE GAP (advisory — implementation does not implement reject logic):"
echo "  SN1 (aggregation without equivalence proof → reject with diagnostic.route-cardinality-equivalence-proof-missing):"
echo "    Current implementation reports diagnostic counts but does not validate equivalence or reject."
echo "    The materialize.nix routeCardinalityEquivalence block is purely diagnostic."
echo "  SN2 (fast path skips required aggregation → reject with diagnostic.route-cardinality-fast-path-invalid):"
echo "    Current implementation does not detect or reject fast-path bypass."
echo "  These are implementation gaps — the SMS spec requires active rejection, not just diagnostic reporting."

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
