#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-350-HDS-010-SDS-010-SMS-060
# Focused construction regression: protected parent-prefix derivation identity

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

fail() {
  printf 'FAIL FS-350-HDS-010-SDS-010-SMS-060: %s\n' "$*" >&2
  exit 1
}

command -v jq >/dev/null 2>&1 || fail "missing jq"
command -v nix >/dev/null 2>&1 || fail "missing nix"

sed "s|__REPO_ROOT__|${repo_root}|g" >"${tmp_dir}/eval.nix" <<'NIX'
let
  lib = import <nixpkgs/lib>;
  self = { outPath = __REPO_ROOT__; };
  routeGroups = import (__REPO_ROOT__ + "/implementation/lib/routing/internal-routes/route-groups.nix") {
    inherit lib self;
  };
  resolveGroups = import (__REPO_ROOT__ + "/implementation/lib/routing/internal-routes/site-plan/resolve-groups.nix") {
    inherit lib self;
  };
  sourceHelpers = import (__REPO_ROOT__ + "/implementation/lib/routing/internal-routes/site-plan/source-rows-helpers.nix") {
    inherit lib;
    mode = "none";
    nodes = { };
    remotePrefixFacts = {
      uplinksByNode = { };
      uplinksByAccess = { };
      ownConnectedPrefixSetByNode = { };
      overlayPolicyAllowedNodes = { };
      overlayAllowedNodes = { };
    };
  };
  sourceRows = [
    {
      family = 6;
      owner = "access-shared";
      netName = "vlan2";
      kind = "runtime-routed-prefix";
      authorityClass = "routed-client-prefix";
      sourceFile = "/run/secrets/delegated-parent";
      prefixName = "vlan2-public";
      delegatedPrefixLength = 48;
      perTenantPrefixLength = 64;
      slot = 2;
      prefixPostfix = "abcd";
      via6 = "fd42::1";
    }
    {
      family = 6;
      owner = "access-shared";
      netName = "vlan3";
      kind = "runtime-routed-prefix";
      authorityClass = "routed-client-prefix";
      sourceFile = "/run/secrets/delegated-parent";
      prefixName = "vlan3-public";
      delegatedPrefixLength = 48;
      perTenantPrefixLength = 64;
      slot = 3;
      via6 = "fd42::1";
    }
  ];
  normalized = map sourceHelpers.normalizeTenantEntry sourceRows;
  enriched = map sourceHelpers.enrichEntry normalized;
  built = routeGroups.build {
    topo = { links = { }; };
    mode = "none";
    entries = enriched;
    mkRoute4 = _: throw "unexpected IPv4 route";
    mkRoute6 = _: throw "unexpected static IPv6 route";
    linkName = "p2p-core-access";
    via6 = "fd42::1";
  };
  resolvedIdentityRows = map (entry: entry // {
    nodeName = "core";
    linkName = "p2p-core-access";
    via6 = "fd42::1";
  }) enriched;
in
{
  routes = built.routes6;
  atomIds = map (entry: entry.routeAtom.id) enriched;
  nextHopIdentityKeys = map resolveGroups.nextHopIdentityKey resolvedIdentityRows;
  normalizedTenants = map (entry: entry.tenant or null) normalized;
}
NIX

result="$(NIX_PATH="nixpkgs=$(nix eval --raw nixpkgs#path)" nix eval --impure --json -f "${tmp_dir}/eval.nix" 2>&1)" \
  || fail "Nix evaluation failed: ${result}"

jq -e '
  .routes == [
    {
      family: 6,
      sourceFile: "/run/secrets/delegated-parent",
      tenant: "vlan2",
      delegatedPrefixLength: 48,
      perTenantPrefixLength: 64,
      slot: 2,
      prefixName: "vlan2-public",
      prefixPostfix: "abcd",
      proto: "internal",
      via6: "fd42::1",
      intent: {
        kind: "runtime-routed-prefix-return",
        source: "intent-routed-prefix",
        accessNode: "access-shared",
        authorityClass: "routed-client-prefix",
        downstreamExport: {
          allowed: true,
          reason: "authority-class-allows-downstream-export"
        }
      }
    },
    {
      family: 6,
      sourceFile: "/run/secrets/delegated-parent",
      tenant: "vlan3",
      delegatedPrefixLength: 48,
      perTenantPrefixLength: 64,
      slot: 3,
      prefixName: "vlan3-public",
      proto: "internal",
      via6: "fd42::1",
      intent: {
        kind: "runtime-routed-prefix-return",
        source: "intent-routed-prefix",
        accessNode: "access-shared",
        authorityClass: "routed-client-prefix",
        downstreamExport: {
          allowed: true,
          reason: "authority-class-allows-downstream-export"
        }
      }
    }
  ]
' <<<"${result}" >/dev/null || fail "runtime routes did not preserve exact tenant derivation metadata"

jq -e '.normalizedTenants == ["vlan2", "vlan3"]' <<<"${result}" >/dev/null \
  || fail "tenant identity was not preserved from the modeled network owner"

jq -e '(.atomIds | length) == 2 and .atomIds[0] != .atomIds[1]' <<<"${result}" >/dev/null \
  || fail "different tenant slots collapsed to the same route-atom identity"

jq -e '(.nextHopIdentityKeys | length) == 2 and .nextHopIdentityKeys[0] != .nextHopIdentityKeys[1]' <<<"${result}" >/dev/null \
  || fail "different tenant slots collapsed to the same next-hop equivalence identity"

printf '%s\n' "OK FS-350-HDS-010-SDS-010-SMS-060 runtime delegated-route metadata"
