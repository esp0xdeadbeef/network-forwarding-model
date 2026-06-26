#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-500-HDS-010-SDS-010-SMS-030
# GAMP-SCOPE: software-module-test
# Focused construction test: reachability decision reason diagnostic.
# SMS-030 verifies that each reachability decision's reason (modeled policy,
# selected path, missing predicate) is named in diagnostics, and that
# allowed decisions without a model reason are rejected.
# Seeded negatives are active.

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
      local.ipv4 = "10.60.0.0/24";
      p2p.ipv4 = "10.60.1.0/24";
    };
    attachments = [
      { unit = "access-app"; kind = "tenant"; name = "app"; }
      { unit = "access-db"; kind = "tenant"; name = "db"; }
    ];
    domains = {
      externals = [ { kind = "external"; name = "wan"; } ];
      tenants = [
        { kind = "tenant"; name = "app"; ipv4 = "10.60.20.0/24"; }
        { kind = "tenant"; name = "db"; ipv4 = "10.60.30.0/24"; }
      ];
    };

    communicationContract = {
      allowedRelations = [
        {
          id = "allow-app-to-wan";
          priority = 100;
          from = { kind = "tenant"; name = "app"; };
          to = { kind = "external"; uplinks = [ "wan" ]; };
          trafficType = "any";
          action = "allow";
        }
        {
          id = "reject-db-to-wan";
          priority = 100;
          from = { kind = "tenant"; name = "db"; };
          to = { kind = "external"; uplinks = [ "wan" ]; };
          trafficType = "any";
          action = "reject";
        }
      ];
      relations = [
        {
          id = "allow-app-to-wan";
          priority = 100;
          from = { kind = "tenant"; name = "app"; };
          to = { kind = "external"; uplinks = [ "wan" ]; };
          trafficType = "any";
          action = "allow";
        }
        {
          id = "reject-db-to-wan";
          priority = 100;
          from = { kind = "tenant"; name = "db"; };
          to = { kind = "external"; uplinks = [ "wan" ]; };
          trafficType = "any";
          action = "reject";
        }
      ];
    };

    trafficPaths = [
      # P1 (allowed): valid allow path with matching relation — reason: allow-app-to-wan
      {
        relationId = "allow-app-to-wan";
        action = "allow";
        source = { kind = "tenant"; name = "app"; };
        destination = { kind = "public-ipv4"; ipv4 = "93.184.216.34"; };
        nodePath = [ "access-app" "downstream" "policy" "upstream" "core-wan" ];
      }

      # SN1: path references non-existent relation (allowed decision without model reason)
      # Expected: diagnostic with missingEvidence=true naming the missing reason
      {
        relationId = "non-existent-allow";
        action = "allow";
        source = { kind = "tenant"; name = "app"; };
        destination = { kind = "public-ipv4"; ipv4 = "1.1.1.1"; };
        nodePath = [ "access-app" "downstream" "policy" "upstream" "core-wan" ];
      }

      # MR1: path contradicts modeled policy (action=allow vs relation=reject)
      # Expected: diagnostic naming the conflicting policy (reject-db-to-wan)
      # and the contradiction reason
      {
        relationId = "reject-db-to-wan";
        action = "allow";
        source = { kind = "tenant"; name = "db"; };
        destination = { kind = "public-ipv4"; ipv4 = "8.8.8.8"; };
        nodePath = [ "access-db" "downstream" "policy" "upstream" "core-wan" ];
      }

      # P2 (denied): valid reject path — reason: reject-db-to-wan (modeled policy deny)
      {
        relationId = "reject-db-to-wan";
        action = "reject";
        source = { kind = "tenant"; name = "db"; };
        destination = { kind = "public-ipv4"; ipv4 = "4.4.4.4"; };
        nodePath = [ "access-db" "downstream" "policy" "upstream" "core-wan" ];
      }
    ];

    transit.ordering = [
      [ "access-app" "downstream" ]
      [ "access-db" "downstream" ]
      [ "downstream" "policy" ]
      [ "policy" "upstream" ]
      [ "upstream" "core-wan" ]
    ];

    units = {
      access-app.role = "access";
      access-db.role = "access";
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
pass_timed "fs-500-hds-010-sds-010-sms-030:compile" "${start_ms}"

# SMS-030: Reachability Decision Reason Diagnostic
#
# P1/MR1: Each decision's reason (modeled policy, missing predicate) is named
#         in diagnostics. Verified: diagnostics include relatedPath (relationId)
#         and either missingEvidence or contractContradiction flag.
#
# P2/MR2: Allowed decision without model reason is rejected.
#         Verified: path with non-existent relationId is in invalidPaths.
#
# SN1: allowed decision without model reason → diagnostic with missingEvidence=true
#      naming the source, destination, and decision type.
#      Verified: non-existent-allow path produces missingEvidence diagnostic
#      naming the path's relationId.
#
# FC1: Required model reason or missing predicate cannot be named → diagnostic emitted.
#      Verified: every invalid path has a corresponding diagnostic.
#
# Known gap (SN2): CONDITIONAL_RUNTIME_FACTS_OMITTED — the trafficPathValidation
# module does not handle conditional/runtime-fact decisions. The SMS predicate
# for conditional decision runtime-fact naming is not implemented at this CMC layer.
# See SMS Self-Check for trace-local correction.

# Write jq filter to temp file to avoid shell quoting issues
jq_filter="${tmpdir}/filter.jq"
cat >"${jq_filter}" <<'JQ'
.enterprise.acme.site.ams as $site
| $site.trafficPathValidation as $tv
| ($tv | type == "object")
and ($tv.validPathCount >= 1)
and ($tv.invalidPathCount >= 2)
and ([ $tv.validPaths[] | select(.relationId == "allow-app-to-wan") ] | length == 1)
and ([ $tv.validPaths[] | select(.relationId == "reject-db-to-wan" and .action == "reject") ] | length == 1)
and ([ $tv.invalidPaths[] | select(.relationId == "non-existent-allow") ] | length == 1)
and ([ $tv.invalidPaths[] | select(.relationId == "reject-db-to-wan" and .action == "allow") ] | length == 1)
and ([ $tv.diagnostics[] | select(.missingEvidence == true and (.message | contains("non-existent-allow"))) ] | length >= 1)
and ([ $tv.diagnostics[] | select(.contractContradiction == true and .pathAction == "allow" and .relationAction == "reject" and (.message | contains("reject-db-to-wan"))) ] | length >= 1)
and ($tv.invalidPathCount == ([ $tv.diagnostics[] | select(.severity == "error") ] | length))
and ([ $tv.diagnostics[] | select(.relatedPath == "allow-app-to-wan") ] | length == 0)
and ([ $tv.diagnostics[] | select(.relatedPath == "reject-db-to-wan" and .contractContradiction == true and .pathAction == "allow" and .relationAction == "reject") ] | length == 1)
JQ

jq -e -f "${jq_filter}" "${output_json}" >/dev/null || {
  echo "FAIL FS-500-HDS-010-SDS-010-SMS-030: decision reason diagnostic incorrect" >&2
  jq '.enterprise.acme.site.ams.trafficPathValidation' "${output_json}" >&2
  exit 1
}

echo "PASS: FS-500-HDS-010-SDS-010-SMS-030 — decision reason diagnostic verified"
echo "  P1 (reason naming): diagnostics name relatedPath and reason type (missingEvidence/contractContradiction)"
echo "  P2 (no false positives): valid paths have no diagnostics"
echo "  MR1 (policy reason): allowed path names allow-app-to-wan; denied path names reject-db-to-wan"
echo "  SN1 (missing reason): non-existent relation rejected with missingEvidence diagnostic"
echo "  FC1 (diagnostic coverage): every invalid path has a diagnostic, no silent failures"
echo "  FC2 (contract contradiction): action mismatch named with conflicting policy reason"
echo "  NOTE: SN2 (CONDITIONAL_RUNTIME_FACTS_OMITTED) — not implemented at this CMC layer (known gap)"
pass_timed "fs-500-hds-010-sds-010-sms-030"
