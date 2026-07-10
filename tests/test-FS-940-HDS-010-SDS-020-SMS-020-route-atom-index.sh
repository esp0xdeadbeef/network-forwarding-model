#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-940-HDS-010-SDS-020-SMS-020
# Construction test: Route Atom Index
#
# SMS-020 owns the route-atom-index submodule that builds per-site route atom
# records before later planner stages. Each atom preserves source/uplink/overlay/
# runtime identity with explicit aggregationClass and exceptionClass.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  echo "FAIL route-atom-index: $*" >&2
  exit 1
}

pass() {
  echo "  PASS: $*"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

require_cmd jq
require_cmd nix
require_cmd rg

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

write_source_rows_fixture() {
  local path="$1"
  local entries_expr="$2"
  local mode="${3:-prefix-summary}"
  cat >"${path}" <<NIX
let
  helpers = import ${repo_root}/implementation/lib/routing/internal-routes/site-plan/source-rows-helpers.nix {
    lib = builtins // { optionalAttrs = cond: attrs: if cond then attrs else {}; };
    mode = "${mode}";
    nodes = {};
    remotePrefixFacts = { uplinksByNode = {}; uplinksByAccess = {}; ownConnectedPrefixSetByNode = {}; overlayPolicyAllowedNodes = {}; overlayAllowedNodes = {}; };
  };
  entries = ${entries_expr};
  enriched = map (entry: helpers.enrichEntry entry) entries;
  atoms = map (entry: entry.routeAtom or {}) enriched;
  classes = builtins.groupBy (a: a.aggregationClass or "unknown") atoms;
  classCounts = builtins.mapAttrs (_: xs: builtins.length xs) classes;
  exceptionClasses = builtins.groupBy (a: a.exceptionClass or "unknown") atoms;
  exceptionClassCounts = builtins.mapAttrs (_: xs: builtins.length xs) exceptionClasses;
in {
  atomCount = builtins.length atoms;
  atoms = atoms;
  aggregationClasses = classCounts;
  requiredFieldsPresent = builtins.all
    (a:
      builtins.all (f: builtins.hasAttr f a) [
        "id" "family" "destination" "sourceFile" "owner"
        "kind" "overlay" "uplink" "exceptionClass" "aggregationClass"
      ])
    atoms;
  defaultFieldsNull = builtins.all
    (a:
      a.family != null && a.owner != null && a.kind != null &&
      a.exceptionClass != null && a.aggregationClass != null)
    atoms;
  exceptionClassCounts = exceptionClassCounts;
}
NIX
}

echo "=== FS-940-HDS-010-SDS-020-SMS-020 Route Atom Index ==="

# P1: Tenant entries get prefix-summary-eligible aggregation and none exception
echo "--- P1: Tenant entry atom enrichment ---"
write_source_rows_fixture "${tmp_dir}/p1-tenant.nix" '[
  { family = "ipv4"; dst = "10.0.1.0/24"; owner = "site-a-tenant-trusted"; kind = "tenant"; }
]'
p1_json="$(nix eval --json -f "${tmp_dir}/p1-tenant.nix")" || fail "P1 evaluation failed"
jq -e '.atomCount == 1' <<<"${p1_json}" >/dev/null || fail "P1: expected 1 atom"
jq -e '.atoms[0].aggregationClass == "prefix-summary-eligible"' <<<"${p1_json}" >/dev/null || fail "P1: expected prefix-summary-eligible"
jq -e '.atoms[0].exceptionClass == "none"' <<<"${p1_json}" >/dev/null || fail "P1: expected exceptionClass=none"
jq -e '.atoms[0].kind == "tenant"' <<<"${p1_json}" >/dev/null || fail "P1: expected kind=tenant"
pass "P1: tenant entry enriched correctly"

# P2: P2P entries get exact-only aggregation and point-to-point-exact exception
echo "--- P2: P2P entry atom enrichment ---"
write_source_rows_fixture "${tmp_dir}/p2-p2p.nix" '[
  { family = "ipv4"; dst = "10.255.0.0/24"; owner = "p2p-pool"; kind = "p2p"; }
]'
p2_json="$(nix eval --json -f "${tmp_dir}/p2-p2p.nix")" || fail "P2 evaluation failed"
jq -e '.atoms[0].aggregationClass == "exact-only"' <<<"${p2_json}" >/dev/null || fail "P2: expected exact-only"
jq -e '.atoms[0].exceptionClass == "point-to-point-exact"' <<<"${p2_json}" >/dev/null || fail "P2: expected point-to-point-exact"
pass "P2: P2P entry enriched correctly"

# P3: Overlay entries get exact-only + overlay-scope-exact
echo "--- P3: Overlay entry atom enrichment ---"
write_source_rows_fixture "${tmp_dir}/p3-overlay.nix" '[
  { family = "ipv4"; dst = "10.80.0.0/24"; owner = "nebula-site"; kind = "overlay"; overlay = "nebula"; peerSite = "peer-site"; }
]'
p3_json="$(nix eval --json -f "${tmp_dir}/p3-overlay.nix")" || fail "P3 evaluation failed"
jq -e '.atoms[0].aggregationClass == "exact-only"' <<<"${p3_json}" >/dev/null || fail "P3: expected exact-only"
jq -e '.atoms[0].exceptionClass == "overlay-scope-exact"' <<<"${p3_json}" >/dev/null || fail "P3: expected overlay-scope-exact"
jq -e '.atoms[0].overlay == "nebula"' <<<"${p3_json}" >/dev/null || fail "P3: expected overlay=nebula"
pass "P3: overlay entry enriched correctly"

# P4: Runtime source-file entries get runtime-source-file class
echo "--- P4: Runtime source-file entry ---"
write_source_rows_fixture "${tmp_dir}/p4-sourcefile.nix" '[
  { family = "ipv6"; dst = "2001:db8::/32"; owner = "isp-a"; kind = "tenant"; sourceFile = "routes/isp-a.nix"; }
]'
p4_json="$(nix eval --json -f "${tmp_dir}/p4-sourcefile.nix")" || fail "P4 evaluation failed"
jq -e '.atoms[0].aggregationClass == "runtime-source-file"' <<<"${p4_json}" >/dev/null || fail "P4: expected runtime-source-file"
jq -e '.atoms[0].exceptionClass == "runtime-source-file"' <<<"${p4_json}" >/dev/null || fail "P4: expected runtime-source-file exception"
pass "P4: runtime source-file entry enriched correctly"

# P5: Selected-uplink entries get selected-uplink-exact exception
echo "--- P5: Selected-uplink entry ---"
write_source_rows_fixture "${tmp_dir}/p5-uplink.nix" '[
  { family = "ipv4"; dst = "0.0.0.0/0"; owner = "isp-a"; kind = "tenant"; uplink = "isp-a-uplink"; }
]'
p5_json="$(nix eval --json -f "${tmp_dir}/p5-uplink.nix")" || fail "P5 evaluation failed"
jq -e '.atoms[0].exceptionClass == "selected-uplink-exact"' <<<"${p5_json}" >/dev/null || fail "P5: expected selected-uplink-exact"
pass "P5: selected-uplink entry enriched correctly"

# P6: All required fields present on every atom
echo "--- P6: Required fields present ---"
jq -e '.requiredFieldsPresent == true' <<<"${p1_json}" >/dev/null || fail "P6: required fields missing on tenant"
jq -e '.requiredFieldsPresent == true' <<<"${p2_json}" >/dev/null || fail "P6: required fields missing on p2p"
jq -e '.requiredFieldsPresent == true' <<<"${p3_json}" >/dev/null || fail "P6: required fields missing on overlay"
pass "P6: required fields present on all atoms"

# P7: Default fields are never null (id, family, owner, kind, exceptionClass, aggregationClass)
echo "--- P7: Default fields non-null ---"
jq -e '.defaultFieldsNull == true' <<<"${p1_json}" >/dev/null || fail "P7: null default field on tenant"
jq -e '.defaultFieldsNull == true' <<<"${p2_json}" >/dev/null || fail "P7: null default field on p2p"
jq -e '.defaultFieldsNull == true' <<<"${p3_json}" >/dev/null || fail "P7: null default field on overlay"
pass "P7: default fields never null"

# P8: Atom IDs are deterministic stable strings
echo "--- P8: Deterministic atom IDs ---"
write_source_rows_fixture "${tmp_dir}/p8-id.nix" '[
  { family = "ipv4"; dst = "10.0.1.0/24"; owner = "site-a-tenant-trusted"; kind = "tenant"; }
]'
p8a_json="$(nix eval --json -f "${tmp_dir}/p8-id.nix")" || fail "P8a evaluation failed"
id_a="$(jq -r '.atoms[0].id' <<<"${p8a_json}")"
p8b_json="$(nix eval --json -f "${tmp_dir}/p8-id.nix")" || fail "P8b evaluation failed"
id_b="$(jq -r '.atoms[0].id' <<<"${p8b_json}")"
[[ "${id_a}" == "${id_b}" ]] || fail "P8: atom ID not deterministic: ${id_a} vs ${id_b}"
pass "P8: atom IDs deterministic"

# P9: Multi-entry fixture produces correct aggregation class counts
echo "--- P9: Aggregation class counts ---"
write_source_rows_fixture "${tmp_dir}/p9-multi.nix" '[
  { family = "ipv4"; dst = "10.0.1.0/24"; owner = "tenant-a"; kind = "tenant"; }
  { family = "ipv4"; dst = "10.0.2.0/24"; owner = "tenant-b"; kind = "tenant"; }
  { family = "ipv4"; dst = "10.255.0.0/24"; owner = "p2p-pool"; kind = "p2p"; }
  { family = "ipv4"; dst = "10.80.0.0/24"; owner = "overlay-site"; kind = "overlay"; overlay = "nebula"; }
]'
p9_json="$(nix eval --json -f "${tmp_dir}/p9-multi.nix")" || fail "P9 evaluation failed"
jq -e '.atomCount == 4' <<<"${p9_json}" >/dev/null || fail "P9: expected 4 atoms"
jq -e '.["aggregationClasses"]["prefix-summary-eligible"] == 2' <<<"${p9_json}" >/dev/null || fail "P9: expected 2 prefix-summary-eligible"
jq -e '.["aggregationClasses"]["exact-only"] == 2' <<<"${p9_json}" >/dev/null || fail "P9: expected 2 exact-only"
pass "P9: multi-entry counts correct"

# P10: Empty entries produce zero atoms (no crash)
echo "--- P10: Empty entries ---"
write_source_rows_fixture "${tmp_dir}/p10-empty.nix" '[]'
p10_json="$(nix eval --json -f "${tmp_dir}/p10-empty.nix")" || fail "P10 evaluation failed"
jq -e '.atomCount == 0' <<<"${p10_json}" >/dev/null || fail "P10: expected 0 atoms"
pass "P10: empty entries handled cleanly"

# SN1: Duplicate route atom IDs across different entries are distinguishable
echo "--- SN1: Duplicate detection via routeAtomId fields ---"
write_source_rows_fixture "${tmp_dir}/sn1-dup.nix" '[
  { family = "ipv4"; dst = "10.0.1.0/24"; owner = "tenant-a"; kind = "tenant"; }
  { family = "ipv4"; dst = "10.0.1.0/24"; owner = "tenant-a"; kind = "tenant"; }
]'
sn1_json="$(nix eval --json -f "${tmp_dir}/sn1-dup.nix")" || fail "SN1 evaluation failed"
jq -e '.atomCount == 2' <<<"${sn1_json}" >/dev/null || fail "SN1: expected 2 atoms for duplicates"
id1="$(jq -r '.atoms[0].id' <<<"${sn1_json}")"
id2="$(jq -r '.atoms[1].id' <<<"${sn1_json}")"
[[ "${id1}" == "${id2}" ]] || fail "SN1: duplicate entries should produce same atom ID; got ${id1} vs ${id2}"
pass "SN1: duplicate entries produce identical atom IDs"

# SN2: Missing family/owner/kind still produces an atom (graceful null handling)
echo "--- SN2: Minimal entry with missing fields ---"
write_source_rows_fixture "${tmp_dir}/sn2-minimal.nix" '[
  { }
]'
sn2_json="$(nix eval --json -f "${tmp_dir}/sn2-minimal.nix")" || fail "SN2 evaluation failed"
jq -e '.atomCount == 1' <<<"${sn2_json}" >/dev/null || fail "SN2: expected 1 atom even for minimal entry"
pass "SN2: minimal entry still produces atom record"

echo "PASS FS-940-HDS-010-SDS-020-SMS-020 route-atom-index"
