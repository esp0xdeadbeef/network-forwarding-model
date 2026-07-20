#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-940-HDS-010-SDS-020-SMS-030
# Construction test: Source Eligibility Matrix

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"

fail() {
  echo "FAIL source-eligibility-matrix: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

require_cmd jq
require_cmd nix

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

write_main_fixture() {
  local path="$1"
  cat >"${path}" <<'NIX'
let
  lib = import <nixpkgs/lib>;
  repoRoot = REPO_ROOT_PLACEHOLDER;
  sourceRows = import (repoRoot + "/implementation/lib/routing/internal-routes/site-plan/source-rows.nix") { inherit lib; };
  helpersModule = import (repoRoot + "/implementation/lib/routing/internal-routes/site-plan/source-rows-helpers.nix") {
    inherit lib;
    mode = "none";
    nodes = {
      "access-a" = { role = "access"; };
      "ds-1" = { role = "downstream-selector"; };
      "ds-2" = { role = "downstream-selector"; };
      "ds-3" = { role = "downstream-selector"; };
      "core-isp-a" = {
        role = "core";
        uplinks.internet-vlan4 = { ipv4 = [ "0.0.0.0/0" ]; ipv6 = [ "::/0" ]; };
        external = "internet-vlan4";
      };
      "core-isp-b" = {
        role = "core";
        uplinks.internet-vlan5 = { ipv4 = [ "0.0.0.0/0" ]; ipv6 = [ "::/0" ]; };
        external = "internet-vlan5";
      };
    };
    remotePrefixFacts = {
      uplinksByNode = {
        "access-a" = [];
        "ds-1" = [];
        "ds-2" = [];
        "ds-3" = [];
        "core-isp-a" = ["internet-vlan4"];
        "core-isp-b" = ["internet-vlan5"];
      };
      uplinksByAccess = { "access-a" = ["internet-vlan4"]; };
      overlayPolicyAllowedNodes = {};
      overlayAllowedNodes = {};
      ownConnectedPrefixSetByNode = {};
    };
  };
  nodes = {
    "access-a" = { role = "access"; };
    "ds-1" = { role = "downstream-selector"; };
    "ds-2" = { role = "downstream-selector"; };
    "ds-3" = { role = "downstream-selector"; };
    "core-isp-a" = {
      role = "core";
      uplinks.internet-vlan4 = { ipv4 = [ "0.0.0.0/0" ]; ipv6 = [ "::/0" ]; };
      external = "internet-vlan4";
    };
    "core-isp-b" = {
      role = "core";
      uplinks.internet-vlan5 = { ipv4 = [ "0.0.0.0/0" ]; ipv6 = [ "::/0" ]; };
      external = "internet-vlan5";
    };
  };
  nodeNames = builtins.attrNames nodes;
  remotePrefixFacts = {
    uplinksByNode = {
      "access-a" = [];
      "ds-1" = [];
      "ds-2" = [];
      "ds-3" = [];
      "core-isp-a" = ["internet-vlan4"];
      "core-isp-b" = ["internet-vlan5"];
    };
    uplinksByAccess = { "access-a" = ["internet-vlan4"]; };
    overlayPolicyAllowedNodes = {};
    overlayAllowedNodes = {};
    ownConnectedPrefixSetByNode = {};
    tenantOwnerEntries = [
      { family = 4; owner = "access-a"; dst = "10.3.172.0/24"; kind = "tenant"; }
      { family = 6; owner = "access-a"; dst = "fd42:03ac:50::/64"; kind = "tenant"; }
    ];
    p2pEntries = [];
    overlayRouteEntries = [];
    serviceRouteScopesByOwner = { "access-a" = []; };
  };
  result = sourceRows.build {
    mode = "none";
    inherit nodeNames nodes remotePrefixFacts;
    includeP2p = false;
    includeTenant = true;
    includeOverlay = false;
  };
  remoteGroupValues = builtins.attrValues result.remoteGroups;
in {
  diagnostics = result.diagnostics;
  sourceEligibility = result.diagnostics.sourceEligibilityMatrix;
  remoteGroupKeys = builtins.attrNames result.remoteGroups;
  remoteGroupValues = remoteGroupValues;
  nodeGroupCounts = builtins.listToAttrs (map (nodeName: {
    name = nodeName;
    value = builtins.length (builtins.filter (group: group.nodeName == nodeName) remoteGroupValues);
  }) nodeNames);
  entriesByKind = result.entriesByKind;
  entry0Eligible = builtins.filter (n: helpersModule.sourceEligibleForEntry n (builtins.elemAt result.entriesByKind 0)) nodeNames;
  entry1Eligible = builtins.filter (n: helpersModule.sourceEligibleForEntry n (builtins.elemAt result.entriesByKind 1)) nodeNames;
}
NIX
  sed -i "s|REPO_ROOT_PLACEHOLDER|${repo_root}|g" "${path}"
}

write_lost_uplink_fixture() {
  local path="$1"
  cat >"${path}" <<'NIX'
let
  lib = import <nixpkgs/lib>;
  repoRoot = REPO_ROOT_PLACEHOLDER;
  helpersModule = import (repoRoot + "/implementation/lib/routing/internal-routes/site-plan/source-rows-helpers.nix") {
    inherit lib;
    mode = "none";
    nodes = {
      "core-isp-a" = {
        role = "core";
        uplinks.internet-vlan4 = { ipv4 = [ "0.0.0.0/0" ]; ipv6 = [ "::/0" ]; };
        external = "internet-vlan4";
      };
      "core-isp-b" = {
        role = "core";
        uplinks.internet-vlan5 = { ipv4 = [ "0.0.0.0/0" ]; ipv6 = [ "::/0" ]; };
        external = "internet-vlan5";
      };
    };
    remotePrefixFacts = {
      uplinksByNode = {
        "core-isp-a" = ["internet-vlan4"];
        "core-isp-b" = ["internet-vlan5"];
      };
      uplinksByAccess = { "access-a" = ["internet-vlan4"]; };
      overlayPolicyAllowedNodes = {};
      overlayAllowedNodes = {};
      ownConnectedPrefixSetByNode = {};
    };
  };
  entryRequiringIspA = {
    owner = "access-a";
    kind = "tenant";
    family = 4;
    dst = "10.0.0.0/24";
  };
in {
  coreIspAEligible = helpersModule.sourceEligibleForEntry "core-isp-a" entryRequiringIspA;
  coreIspBNotEligible = !(helpersModule.sourceEligibleForEntry "core-isp-b" entryRequiringIspA);
  ispAReachable = helpersModule.tenantReachableFromNode "core-isp-a" entryRequiringIspA;
  ispBNotReachable = !(helpersModule.tenantReachableFromNode "core-isp-b" entryRequiringIspA);
}
NIX
  sed -i "s|REPO_ROOT_PLACEHOLDER|${repo_root}|g" "${path}"
}

# --- P1-P12: Happy path and matrix structure ---
fixture="${tmp_dir}/s1.nix"
write_main_fixture "${fixture}"
json="$(nix eval --json -f "${fixture}")" || fail "P1 evaluation failed"

jq -e '.sourceEligibility.groupedOncePerSite == true' <<<"${json}" >/dev/null \
  || fail "P1: source eligibility matrix not marked as grouped once per site"

jq -e '.sourceEligibility.sms == "FS-940-HDS-010-SDS-020-SMS-030"' <<<"${json}" >/dev/null \
  || fail "P2: SMS identity not recorded in diagnostics"

jq -e '.sourceEligibility.authority == "site-plan/source-rows"' <<<"${json}" >/dev/null \
  || fail "P3: authority not recorded"

jq -e '.sourceEligibility.keyFields | contains(["sourceNode","routeAtomId","owner","kind","overlay","uplink","access","serviceName"])' <<<"${json}" >/dev/null \
  || fail "P4: key fields missing required scope fields"

jq -e '.sourceEligibility.eligiblePairCount > 0' <<<"${json}" >/dev/null \
  || fail "P5: zero eligible pairs"

jq -e '.sourceEligibility.rejectedPairCount > 0' <<<"${json}" >/dev/null \
  || fail "P6: zero rejected pairs but some nodes should be ineligible"

jq -e '.entry0Eligible | contains(["core-isp-a"])' <<<"${json}" >/dev/null \
  || fail "P7: core-isp-a should be eligible (has matching uplink)"

jq -e '(.entry0Eligible | contains(["core-isp-b"]) | not)' <<<"${json}" >/dev/null \
  || fail "P8: core-isp-b should NOT be eligible (different uplink)"

jq -e '.entry0Eligible | contains(["ds-1","ds-2","ds-3"])' <<<"${json}" >/dev/null \
  || fail "P9: all downstream-selectors should be eligible"

jq -e '(.entry0Eligible | contains(["access-a"]) | not)' <<<"${json}" >/dev/null \
  || fail "P10: access node should not be eligible for its own prefix"

jq -e '.entriesByKind | length == 2' <<<"${json}" >/dev/null \
  || fail "P11: expected 2 tenant entries"

jq -e '
  .entriesByKind | map(.routeAtom | has("id") and has("family") and has("destination") and has("sourceFile") and has("owner") and has("kind") and has("overlay") and has("uplink") and has("exceptionClass") and has("aggregationClass")) | all
' <<<"${json}" >/dev/null \
  || fail "P12: route atom missing required fields"

# --- Seeded Negatives ---

# SN1: Source eligibility recalculated per-node instead of once per site
jq -e '.sourceEligibility.groupedOncePerSite == true' <<<"${json}" >/dev/null \
  || fail "SN1: groupedOncePerSite must be true (once-per-site computation)"

jq -e '.sourceEligibility.eligiblePairCount > 1' <<<"${json}" >/dev/null \
  || fail "SN1: eligible pair count too low for site-wide matrix"

# SN2: Source eligibility loses uplink scope during matrix construction
sn2_fixture="${tmp_dir}/sn2.nix"
write_lost_uplink_fixture "${sn2_fixture}"
sn2_json="$(nix eval --json -f "${sn2_fixture}")" || fail "SN2 evaluation failed"

jq -e '.coreIspAEligible == true' <<<"${sn2_json}" >/dev/null \
  || fail "SN2a: core-isp-a should be eligible for isp-a tenant route (matching uplink)"

jq -e '.coreIspBNotEligible == true' <<<"${sn2_json}" >/dev/null \
  || fail "SN2b: core-isp-b NOT eligible for isp-a tenant route (uplink scope preserved)"

jq -e '.ispAReachable == true' <<<"${sn2_json}" >/dev/null \
  || fail "SN2c: isp-a core should be tenant-reachable"

jq -e '.ispBNotReachable == true' <<<"${sn2_json}" >/dev/null \
  || fail "SN2d: isp-b core should NOT be tenant-reachable for isp-a tenant"

echo "PASS FS-940-HDS-010-SDS-020-SMS-030 source eligibility matrix"
