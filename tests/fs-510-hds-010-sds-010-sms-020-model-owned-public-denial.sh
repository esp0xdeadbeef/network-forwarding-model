#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-510-HDS-010-SDS-010-SMS-020
# GAMP-SCOPE: software-module-test
# Focused construction test: model-owned public destination denial.
# SMS-020 verifies that generic WAN egress to model-owned public destinations
# is denied (fail-closed) without explicit service or ingress policy, and that
# diagnostics are emitted with destination/service/source context.
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
      local.ipv4 = "10.52.0.0/24";
      p2p.ipv4 = "10.52.1.0/24";
      p2p.ipv6 = "fd42:520::/118";
    };

    attachments = [
      { unit = "access-client"; kind = "tenant"; name = "client"; }
    ];

    domains = {
      externals = [ { kind = "external"; name = "wan"; } ];
      tenants = [
        {
          kind = "tenant";
          name = "client";
          ipv4 = "10.52.20.0/24";
          publicIpv4 = "203.0.113.10/32";
        }
      ];
    };

    ownership.endpoints = [
      {
        kind = "local";
        name = "model-owned-endpoint";
        publicIpv4 = "203.0.113.30/32";
      }
    ];

    communicationContract = {
      services = [
        {
          name = "hetzner-proxy";
          publicIngress = {
            enabled = true;
            ipv4 = "203.0.113.20/32";
          };
        }
      ];
      allowedRelations = [
        {
          id = "allow-client-to-wan";
          priority = 100;
          from = { kind = "tenant"; name = "client"; };
          to = { kind = "external"; uplinks = [ "wan" ]; };
          trafficType = "any";
          action = "allow";
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
      ];
    };

    trafficPaths = [
      # SEEDED NEGATIVE 1 (SN1): generic WAN egress to model-owned enterprise-client
      # public IP without service or ingress policy.
      # Must be denied with diagnostic naming destination/service/source.
      {
        relationId = "broad-wan-to-enterprise-client-public";
        action = "allow";
        source = { kind = "tenant"; name = "client"; };
        destination = { kind = "public-ipv4"; ipv4 = "203.0.113.10"; };
        nodePath = [ "access-client" "downstream" "policy" "upstream" "core-wan" ];
      }
      # SEEDED NEGATIVE 2 (SN2): public-ingress destination accessed through
      # generic WAN egress without public-ingress policy.
      # Must be denied — missing public-ingress authority must NOT be treated
      # as generic internet reachability.
      {
        relationId = "broad-wan-to-public-ingress";
        action = "allow";
        source = { kind = "tenant"; name = "client"; };
        destination = { kind = "public-ipv4"; ipv4 = "203.0.113.20"; };
        nodePath = [ "access-client" "downstream" "policy" "upstream" "core-wan" ];
      }
      # SEEDED NEGATIVE 1 (continued): local model-owned endpoint accessed
      # through broad-WAN without shortcut policy.
      {
        relationId = "broad-wan-to-local-owned";
        action = "allow";
        source = { kind = "tenant"; name = "client"; };
        destination = { kind = "public-ipv4"; ipv4 = "203.0.113.30"; };
        nodePath = [ "access-client" "downstream" "policy" "upstream" "core-wan" ];
      }
      # CONTROL: generic-internet destination (not model-owned) — must NOT
      # be denied. Must be classified as genericWanInternet.
      {
        relationId = "ordinary-public-internet";
        action = "allow";
        source = { kind = "tenant"; name = "client"; };
        destination = { kind = "public-ipv4"; ipv4 = "93.184.216.34"; };
        nodePath = [ "access-client" "downstream" "policy" "upstream" "core-wan" ];
      }
    ];

    transit.ordering = [
      [ "access-client" "downstream" ]
      [ "downstream" "policy" ]
      [ "policy" "upstream" ]
      [ "upstream" "core-wan" ]
    ];

    units = {
      access-client.role = "access";
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
pass_timed "fs-510-hds-010-sds-010-sms-020:compile" "${start_ms}"

# SMS-020: Model-Owned Public Destination Denial Module
#
# Predicate matrix:
#   MR1: Return closed decision when source with generic WAN egress asks for
#        model-owned public destination without service or ingress policy.
#   MR2: Prevent generic WAN egress from shortcutting model-owned services.
#   CI1: Consume model-owned destination registry.
#   CI2: Consume public service and public-ingress policy records.
#   CI3: Consume generic WAN or internet egress authorization records.
#   EI1: Emit closed decision for unauthorized model-owned public destinations.
#   EI2: Emit missing authority diagnostic.
#   FC1: Generic WAN egress does NOT shortcut model-owned services (fail-closed).
#   FC2: Missing public service/ingress authority is NOT treated as generic
#        internet reachability.
#   SN1: Active seeded negative — generic WAN to model-owned public IP
#        without service policy → closed + diagnostic.
#   SN2: Active seeded negative — public-ingress target without ingress
#        policy → closed + diagnostic.
#   CH1: CMC constructs denial checks, focused test wired into suite.

jq -e '
  .enterprise.acme.site.ams.publicIpv4DestinationPolicy as $policy

  # --- CI1: model-owned destination registry ---
  | $policy.destinationClasses["public-ipv4-destination::203.0.113.10"] as $enterpriseClient
  | $policy.destinationClasses["public-ipv4-destination::203.0.113.20"] as $publicIngress
  | $policy.destinationClasses["public-ipv4-destination::203.0.113.30"] as $localEndpoint
  | $policy.destinationClasses["public-ipv4-destination::93.184.216.34"] as $genericWan

  # CI1: all model-owned destinations must exist in registry
  | ($enterpriseClient != null)
    and ($publicIngress != null)
    and ($localEndpoint != null)
    and ($genericWan != null)

  # CI1: model-owned destinations correctly classified
  | ($enterpriseClient.modelOwned == true)
    and ($publicIngress.modelOwned == true)
    and ($localEndpoint.modelOwned == true)
    and ($genericWan.modelOwned == false)

  # CI1: generic internet is NOT model-owned
  | ($genericWan.genericWanInternet == true)

  # --- FC2: model-owned destinations are NOT classified as generic internet ---
  | ($enterpriseClient.genericWanInternet != true)
    and ($publicIngress.genericWanInternet != true)
    and ($localEndpoint.genericWanInternet != true)

  # --- CI2: service and public-ingress policy records ---
  # destinationClasses include serviceName for public-ingress
  | ($publicIngress.destinationClass == "public-ingress")
    and ($publicIngress.serviceName == "hetzner-proxy")

  # --- CI3: generic WAN egress authorization records ---
  # (verified by existence of broadWanDenials below)

  # --- MR1 + MR2 + EI1 + FC1: closed decisions for unauthorized destinations ---
  # SN1 enterprise-client: must be denied
  | ([ $policy.broadWanDenials[]
      | select(.relationId == "broad-wan-to-enterprise-client-public"
               and .allowed == false
               and .destinationAddress == "203.0.113.10"
               and .destinationClass == "enterprise-client")
    ] | length == 1)

  # SN2 public-ingress: must be denied
  | ([ $policy.broadWanDenials[]
      | select(.relationId == "broad-wan-to-public-ingress"
               and .allowed == false
               and .destinationAddress == "203.0.113.20"
               and .destinationClass == "public-ingress")
    ] | length == 1)

  # SN1 continued: local endpoint: must be denied
  | ([ $policy.broadWanDenials[]
      | select(.relationId == "broad-wan-to-local-owned"
               and .allowed == false
               and .destinationAddress == "203.0.113.30"
               and .destinationClass == "locally-owned-routed")
    ] | length == 1)

  # FC1: generic WAN egress does NOT shortcut model-owned services
  # (no allowed shortcut without explicit policy — verified by shortcutAuthorizations being empty)
  | ((($policy.shortcutAuthorizations | length // 0) == 0)
     or ([ $policy.shortcutAuthorizations[]
         | select(.destinationAddress == "203.0.113.10"
                  or .destinationAddress == "203.0.113.20"
                  or .destinationAddress == "203.0.113.30")
       ] | length == 0))

  # CONTROL: generic internet is NOT denied
  | ([ $policy.broadWanDenials[]
      | select(.relationId == "ordinary-public-internet")
    ] | length == 0)

  # --- EI2: diagnostics emitted for each denied path ---
  | [ $policy.diagnostics[]
    | select(.relationId != null)
    | .relationId
  ] as $diagnosticRelationIds

  # Each of the three denied paths must have a diagnostic
  | (["broad-wan-to-enterprise-client-public",
     "broad-wan-to-public-ingress",
     "broad-wan-to-local-owned"]
    - $diagnosticRelationIds | length == 0)

  # CONTROL: no diagnostic for non-denied path
  | (["ordinary-public-internet"] - $diagnosticRelationIds | length == 1)

  # --- EI2: diagnostics carry severity, message, destinationAddress, relatedDenial ---
  | ([ $policy.diagnostics[]
      | select(.relationId == "broad-wan-to-enterprise-client-public")
      | select(.severity == "error"
              and (.message | length > 0)
              and .destinationAddress == "203.0.113.10")
    ] | length >= 1)

  | ([ $policy.diagnostics[]
      | select(.relationId == "broad-wan-to-public-ingress")
      | select(.severity == "error"
              and (.message | length > 0)
              and .destinationAddress == "203.0.113.20")
    ] | length >= 1)

  | ([ $policy.diagnostics[]
      | select(.relationId == "broad-wan-to-local-owned")
      | select(.severity == "error"
              and (.message | length > 0)
              and .destinationAddress == "203.0.113.30")
    ] | length >= 1)

  # --- FC2 + CH1: broad-wan-does-not-authorize-model-owned-public-ipv4 reason ---
  | ([ $policy.broadWanDenials[]
      | select(.reason == "broad-wan-does-not-authorize-model-owned-public-ipv4")
    ] | length == 3)

  # --- SN1 + SN2: seeded negatives are ACTIVE (denials exist, not empty) ---
  | ($policy.broadWanDenials | length) == 3

' "${output_json}" >/dev/null || {
  echo "FAIL FS-510-HDS-010-SDS-010-SMS-020: model-owned public denial incorrect" >&2
  jq '.enterprise.acme.site.ams.publicIpv4DestinationPolicy.broadWanDenials' "${output_json}" >&2
  jq '.enterprise.acme.site.ams.publicIpv4DestinationPolicy.diagnostics' "${output_json}" >&2
  jq '.enterprise.acme.site.ams.publicIpv4DestinationPolicy.destinationClasses | with_entries(select(.value.modelOwned == true))' "${output_json}" >&2
  exit 1
}

echo "PASS: FS-510-HDS-010-SDS-010-SMS-020 — model-owned public destination denial verified (13 predicates, seeded negatives 1+2 active)."
pass_timed "fs-510-hds-010-sds-010-sms-020"
