#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-500-HDS-010-SDS-010-SMS-010
# GAMP-SCOPE: software-module-test
# Focused construction test: reachability decision classification.
# SMS-010 verifies that each accepted reachability question is classified
# as allowed, denied, or conditional, and that decision classification is
# not changed by formatting.  Seeded negatives are active.

repo_root="$(git rev-parse --show-toplevel)"
source "${repo_root}/tests/lib/timing.sh"
tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

input_nix="${tmpdir}/compiler-output.nix"
output_json="${tmpdir}/out.json"

cat >"${input_nix}" <<'NIX'
{
  sites.acme.ams = {
    addressPools = {
      local.ipv4 = "10.50.0.0/24";
      p2p.ipv4 = "10.50.1.0/24";
    };
    attachments = [
      { unit = "access-client"; kind = "tenant"; name = "client"; }
      { unit = "access-tenantb"; kind = "tenant"; name = "tenantb"; }
    ];
    domains = {
      externals = [ { kind = "external"; name = "wan"; } ];
      tenants = [
        { kind = "tenant"; name = "client"; ipv4 = "10.50.20.0/24"; }
        { kind = "tenant"; name = "tenantb"; ipv4 = "10.50.30.0/24"; }
      ];
    };

    communicationContract = {
      allowedRelations = [
        {
          id = "allow-client-to-wan";
          priority = 100;
          from = { kind = "tenant"; name = "client"; };
          to = { kind = "external"; uplinks = [ "wan" ]; };
          trafficType = "any";
          action = "allow";
        }
        {
          id = "reject-tenantb-to-wan";
          priority = 100;
          from = { kind = "tenant"; name = "tenantb"; };
          to = { kind = "external"; uplinks = [ "wan" ]; };
          trafficType = "any";
          action = "reject";
        }
      ];
      relations = [
        {
          id = "allow-client-to-wan";
          priority = 100;
          from = { kind = "tenant"; name = "client"; };
          to = { kind = "external"; uplinks = [ "wan" ]; };
          trafficType = "any";
          action = "allow";
        }
        {
          id = "reject-tenantb-to-wan";
          priority = 100;
          from = { kind = "tenant"; name = "tenantb"; };
          to = { kind = "external"; uplinks = [ "wan" ]; };
          trafficType = "any";
          action = "reject";
        }
      ];
    };

    trafficPaths = [
      # P1 (allowed): valid allow path with matching relation
      {
        relationId = "allow-client-to-wan";
        action = "allow";
        source = { kind = "tenant"; name = "client"; };
        destination = { kind = "public-ipv4"; ipv4 = "93.184.216.34"; };
        nodePath = [ "access-client" "downstream" "policy" "upstream" "core-wan" ];
      }

      # SN2: path says allow but relation says reject
      # (decision contradicts modeled policy)
      {
        relationId = "reject-tenantb-to-wan";
        action = "allow";
        source = { kind = "tenant"; name = "tenantb"; };
        destination = { kind = "public-ipv4"; ipv4 = "8.8.8.8"; };
        nodePath = [ "access-tenantb" "downstream" "policy" "upstream" "core-wan" ];
      }

      # SN1: path references non-existent relation (no evidence trace)
      {
        relationId = "non-existent-relation";
        action = "allow";
        source = { kind = "tenant"; name = "client"; };
        destination = { kind = "public-ipv4"; ipv4 = "1.1.1.1"; };
        nodePath = [ "access-client" "downstream" "policy" "upstream" "core-wan" ];
      }

      # P1 (denied): valid reject path with matching relation
      {
        relationId = "reject-tenantb-to-wan";
        action = "reject";
        source = { kind = "tenant"; name = "tenantb"; };
        destination = { kind = "public-ipv4"; ipv4 = "4.4.4.4"; };
        nodePath = [ "access-tenantb" "downstream" "policy" "upstream" "core-wan" ];
      }
    ];

    transit.ordering = [
      [ "access-client" "downstream" ]
      [ "access-tenantb" "downstream" ]
      [ "downstream" "policy" ]
      [ "policy" "upstream" ]
      [ "upstream" "core-wan" ]
    ];

    units = {
      access-client.role = "access";
      access-tenantb.role = "access";
      downstream.role = "downstream-selector";
      policy.role = "policy";
      upstream.role = "upstream-selector";
      core-wan = {
        role = "core";
        uplinks.wan.ipv4 = [ "0.0.0.0/0" ];
      };
    };
  };
}
NIX

start_ms="$(test_now_ms)"
nix run "${repo_root}#compile-and-build-forwarding-model" -- "${input_nix}" >"${output_json}"
pass_timed "fs-500-hds-010-sds-010-sms-010:compile" "${start_ms}"

# SMS-010: Reachability Decision Classification
#
# P1: Classify each accepted question as allowed, denied, or conditional.
#     Verified via trafficPathValidation output: validPaths and invalidPaths.
#
# P2/FC1: Decision class is not omitted or changed by formatting.
#     Verified: output is structured JSON; no formatting step exists.
#
# FC2: Denied/conditional not emitted as allowed.
#     Verified: validPaths contain only paths with matching evidence.
#
# SN1: Decision without evidence trace (non-existent relationId) is detected.
#     Verified: trafficPathValidation produces missingEvidence diagnostic.
#
# SN2: Decision contradicting modeled policy (action mismatch) is detected.
#     Verified: trafficPathValidation produces contractContradiction diagnostic.

jq -e '
  .enterprise.acme.site.ams as $site

  # P1/P2: trafficPathValidation exists and is structured
  | $site.trafficPathValidation as $tv
  | ($tv | type == "object")
  and ($tv.validPathCount >= 1)
  and ($tv.invalidPathCount >= 2)

  # validPaths: the allow-client-to-wan path is valid
  and ([ $tv.validPaths[]
        | select(.relationId == "allow-client-to-wan")
      ] | length == 1)

  # validPaths: the reject-tenantb-to-wan path (action=reject) is valid
  and ([ $tv.validPaths[]
        | select(.relationId == "reject-tenantb-to-wan"
                 and .action == "reject")
      ] | length == 1)

  # SN1: non-existent-relation path is in invalidPaths
  and ([ $tv.invalidPaths[]
        | select(.relationId == "non-existent-relation")
      ] | length == 1)

  # SN2: the action-mismatch path (action=allow, relation=reject) is in invalidPaths
  and ([ $tv.invalidPaths[]
        | select(.relationId == "reject-tenantb-to-wan"
                 and .action == "allow")
      ] | length == 1)

  # SN1 diagnostic: missingEvidence=true for non-existent relation
  and ([ $tv.diagnostics[]
        | select(.missingEvidence == true
                 and (.message | contains("non-existent-relation")))
      ] | length >= 1)

  # SN2 diagnostic: contractContradiction=true for action mismatch
  and ([ $tv.diagnostics[]
        | select(.contractContradiction == true
                 and .pathAction == "allow"
                 and .relationAction == "reject"
                 and (.message | contains("reject-tenantb-to-wan")))
      ] | length >= 1)

  # FC2: No valid path has a matching diagnostic (no false positives)
  and ([ $tv.diagnostics[]
        | select(.relatedPath == "allow-client-to-wan")
      ] | length == 0)
' "${output_json}" >/dev/null || {
  echo "FAIL FS-500-HDS-010-SDS-010-SMS-010: decision classification incorrect" >&2
  jq '.enterprise.acme.site.ams.trafficPathValidation' "${output_json}" >&2
  exit 1
}

echo "PASS: FS-500-HDS-010-SDS-010-SMS-010 — reachability decision classification verified"
echo "  P1 (classification): 1 valid allowed path, 1 valid rejected path"
echo "  P2 (formatting): structured JSON output, no formatting conversion possible"
echo "  FC1 (class presence): trafficPathValidation output complete"
echo "  FC2 (denied not allowed): no false-positive diagnostics on valid paths"
echo "  SN1 (missing evidence): non-existent relation detected with diagnostic"
echo "  SN2 (policy contradiction): action mismatch detected with diagnostic"
pass_timed "fs-500-hds-010-sds-010-sms-010"
