#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-380-HDS-010-SDS-010-SMS-020
# GAMP-ID: FS-380-HDS-010-SDS-010-SMS-040
# GAMP-ID: FS-310-HDS-010-SDS-010-SMS-070
# GAMP-SCOPE: software-module-test
#
# Focused construction test for nat44-egress.nix:
#   SMS-020: source scope validation against egress surface, private IPv4 NAT mode records
#   SMS-040: host-only-provider-prefix boundary — host-only prefixes rejected from NAT44 sources
#   SMS-070: translation primitive traces to explicit model/provider translation authority
#
# Seeded negatives:
#   - missing translation mode falls through (no nat44 records)
#   - host-only prefix wrongly used as NAT44 source (filtered out)

repo_root="$(git rev-parse --show-toplevel)"
source "${repo_root}/tests/lib/timing.sh"

start_ms="$(test_now_ms)"
tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

expr_nix="${tmpdir}/nat44-egress-construction.nix"
result_json="${tmpdir}/nat44-egress-construction.json"

cat >"${expr_nix}" <<'NIX'
let
  repoRoot = builtins.getEnv "REPO_ROOT";
  flake = builtins.getFlake ("path:" + repoRoot);
  lib = flake.inputs.nixpkgs.lib;
  semanticNode = import (repoRoot + "/implementation/s88/Site/topology/semantic-node.nix") {
    inherit lib;
    self = { outPath = repoRoot; };
  };

  # --- Minimal site for positive nat44 selection (SMS-020) ---
  baseSite = {
    domains.tenants = [
      { name = "client"; ipv4 = "10.37.20.0/24"; }
    ];
    communicationContract = {
      relations = [
        {
          id = "allow-client-to-wan";
          action = "allow";
          returnBehavior = "symmetric";
          from = { kind = "tenant"; name = "client"; };
          to = { kind = "external"; name = "wan"; };
        }
      ];
    };
  };

  # --- Node with NAT44 translation enabled (SMS-020 acceptance) ---
  nat44Node = {
    role = "core";
    uplinks.wan = {
      egress.ipv4.translation.mode = "nat44";
    };
  };

  # --- Node with masquerade mode (SMS-020: alternative valid mode) ---
  masqueradeNode = {
    role = "core";
    uplinks.wan = {
      egress.ipv4.translation.mode = "masquerade";
    };
  };

  # --- Node with SNAT mode (SMS-020: alternative valid mode) ---
  snatNode = {
    role = "core";
    uplinks.wan = {
      egress.ipv4.translation.mode = "snat";
    };
  };

  # --- Seeded negative: no translation mode set (SMS-020 negative) ---
  noTranslationNode = {
    role = "core";
    uplinks.wan = { };
  };

  # --- Seeded negative: invalid translation mode (SMS-020 negative) ---
  invalidModeNode = {
    role = "core";
    uplinks.wan = {
      egress.ipv4.translation.mode = "bogus-mode";
    };
  };

  buildCore = site: node:
    semanticNode.build {
      nodeName = "core";
      inherit node site;
      role = "core";
      siteUplinkCoreNames = [ "core" ];
      siteUplinkNames = [ "wan" ];
      siteExternalDomains = [ "wan" ];
    };

  # --- SMS-040 host-only boundary site ---
  # Site where tenant "client" has ipv4 = "10.37.20.0/24" AND tenantPrefixOwners
  # classifies "10.37.20.0/24" as host-only-provider-prefix (SMS-040 boundary)
  hostOnlySite = baseSite // {
    tenantPrefixOwners = {
      "4|10.37.20.0/24" = {
        authorityClass = "host-only-provider-prefix";
        owner = "some-access-node";
        family = 4;
        dst = "10.37.20.0/24";
      };
    };
  };

  # --- SMS-040: site with mixed prefixes (one host-only, one not) ---
  mixedSite = {
    domains.tenants = [
      { name = "client"; ipv4 = "10.37.20.0/24"; }
      { name = "dmz"; ipv4 = "10.37.30.0/24"; }
    ];
    communicationContract = {
      relations = [
        {
          id = "allow-client-to-wan";
          action = "allow";
          returnBehavior = "symmetric";
          from = { kind = "tenant"; name = "client"; };
          to = { kind = "external"; name = "wan"; };
        }
        {
          id = "allow-dmz-to-wan";
          action = "allow";
          returnBehavior = "symmetric";
          from = { kind = "tenant"; name = "dmz"; };
          to = { kind = "external"; name = "wan"; };
        }
      ];
    };
    tenantPrefixOwners = {
      "4|10.37.20.0/24" = {
        authorityClass = "host-only-provider-prefix";
        owner = "some-access-node";
      };
      "4|10.37.30.0/24" = {
        authorityClass = "routed-client-prefix";
        owner = "dmz-access-node";
      };
    };
  };

  # Build results
  nat44Result = buildCore baseSite nat44Node;
  masqueradeResult = buildCore baseSite masqueradeNode;
  snatResult = buildCore baseSite snatNode;
  noTranslationResult = buildCore baseSite noTranslationNode;
  invalidModeResult = buildCore baseSite invalidModeNode;
  hostOnlyResult = buildCore hostOnlySite nat44Node;
  mixedResult = buildCore mixedSite nat44Node;

  checks = {
    # SMS-020: private IPv4 NAT mode record emitted with correct sourcePrefixes
    nat44EmitsCorrectRecord =
      nat44Result.egressIntent.nat44.wan == {
        mode = "nat44";
        sourcePrefixes = [ "10.37.20.0/24" ];
        egressSurface = "wan";
      };

    # SMS-020: egressIntent.nat44 has expected structure keys
    nat44HasMode = (nat44Result.egressIntent.nat44.wan.mode or null) == "nat44";
    nat44HasSourcePrefixes = (nat44Result.egressIntent.nat44.wan.sourcePrefixes or []) == [ "10.37.20.0/24" ];
    nat44HasEgressSurface = (nat44Result.egressIntent.nat44.wan.egressSurface or null) == "wan";

    # SMS-020: masquerade mode works correctly
    masqueradeEmitsCorrectRecord =
      masqueradeResult.egressIntent.nat44.wan == {
        mode = "masquerade";
        sourcePrefixes = [ "10.37.20.0/24" ];
        egressSurface = "wan";
      };

    # SMS-020: snat mode works correctly
    snatEmitsCorrectRecord =
      snatResult.egressIntent.nat44.wan == {
        mode = "snat";
        sourcePrefixes = [ "10.37.20.0/24" ];
        egressSurface = "wan";
      };

    # SMS-020 seeded negative: no translation mode → nat44 is empty
    noTranslationProducesEmptyNat44 = noTranslationResult.egressIntent.nat44 == { };

    # SMS-020 seeded negative: invalid translation mode → nat44 is empty
    invalidModeProducesEmptyNat44 = invalidModeResult.egressIntent.nat44 == { };

    # SMS-040: host-only prefix is filtered out → nat44 is empty for host-only-only tenant
    hostOnlyPrefixIsFiltered = hostOnlyResult.egressIntent.nat44 == { };

    # SMS-040: mixed site — only non-host-only prefix survives, host-only is filtered
    mixedOnlyNonHostPrefixSurvives =
      mixedResult.egressIntent.nat44.wan.mode == "nat44"
      && mixedResult.egressIntent.nat44.wan.sourcePrefixes == [ "10.37.30.0/24" ]
      && mixedResult.egressIntent.nat44.wan.egressSurface == "wan";

    # SMS-040: host-only filtered list is recorded when filtering happens
    mixedHostOnlyFiltered =
      (mixedResult.egressIntent.nat44.wan.hostOnlyFiltered or []) == [ "10.37.20.0/24" ];

    # SMS-070: egressIntent.nat44 key exists on eligible nodes (translation authority handoff)
    nat44KeyExists = builtins.hasAttr "nat44" nat44Result.egressIntent;

    # Verify nat66 still works side-by-side (no regression)
    nat66NotAffected = nat44Result.egressIntent.nat66 == { };
  };
in
{
  inherit
    nat44Result masqueradeResult snatResult
    noTranslationResult invalidModeResult
    hostOnlyResult mixedResult
    checks;
}
NIX

REPO_ROOT="${repo_root}" nix eval \
  --extra-experimental-features 'nix-command flakes' \
  --impure --json --file "${expr_nix}" >"${result_json}"

failed_checks="$(jq -r '.checks | to_entries[] | select(.value != true) | .key' "${result_json}")"
if [[ -n "${failed_checks}" ]]; then
  echo "FAIL nat44-egress-construction" >&2
  echo "failed checks:" >&2
  while IFS= read -r failed_check; do
    echo "  ${failed_check}" >&2
  done <<<"${failed_checks}"
  jq '.checks' "${result_json}" >&2
  exit 1
fi

echo "PASS FS-380-HDS-010-SDS-010-SMS-020-nat44-egress"
pass_timed "FS-380-HDS-010-SDS-010-SMS-020-nat44-egress" "${start_ms}"
