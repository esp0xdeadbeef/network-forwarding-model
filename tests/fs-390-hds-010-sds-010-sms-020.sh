#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-390-HDS-010-SDS-010-SMS-020
# GAMP-SCOPE: software-module-test
# Focused construction test: public IPv4 shortcut policy authorization.
# SMS-020 verifies that shortcuts to model-owned public IPv4 destinations
# require explicit public-service reachability, public ingress, or equivalent
# service allow, and rejects shortcuts when policy predicates are missing.

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
      local.ipv4 = "10.39.0.0/24";
      p2p.ipv4 = "10.39.1.0/24";
      p2p.ipv6 = "fd42:390::/118";
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
          ipv4 = "10.39.20.0/24";
          publicIpv4 = "198.51.100.10/32";
        }
      ];
    };

    ownership.endpoints = [
      {
        kind = "local";
        name = "locally-routed-endpoint";
        publicIpv4 = "198.51.100.12/32";
      }
      {
        kind = "provider";
        name = "provider-owned-endpoint";
        providerOwned = true;
        publicIpv4 = "198.51.100.13/32";
      }
    ];

    communicationContract = {
      services = [
        {
          name = "tenant-api";
          publicIpv4 = "198.51.100.11/32";
        }
        {
          name = "public-web";
          publicIngress = {
            enabled = true;
            ipv4 = "198.51.100.14/32";
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
      # POSITIVE: explicit shortcut with publicServicePolicy → authorized
      {
        relationId = "explicit-service-shortcut";
        action = "allow";
        source = { kind = "tenant"; name = "client"; };
        destination = { kind = "public-ipv4"; ipv4 = "198.51.100.11"; };
        shortcutPolicy = "explicit";
        publicServicePolicy = true;
        nodePath = [ "access-client" "downstream" "policy" "upstream" "core-wan" ];
      }
      # SEEDED NEGATIVE 1: model-owned destination without shortcut policy
      # (no shortcutPolicy, no publicServicePolicy, no publicIngressPolicy)
      # → must NOT be authorized, must produce diagnostic
      {
        relationId = "no-policy-to-enterprise-client-public";
        action = "allow";
        source = { kind = "tenant"; name = "client"; };
        destination = { kind = "public-ipv4"; ipv4 = "198.51.100.10"; };
        nodePath = [ "access-client" "downstream" "policy" "upstream" "core-wan" ];
      }
      # SEEDED NEGATIVE 2: model-owned destination (public-ingress) without shortcut policy
      # → must NOT be authorized, must produce diagnostic
      {
        relationId = "no-policy-to-public-ingress";
        action = "allow";
        source = { kind = "tenant"; name = "client"; };
        destination = { kind = "public-ipv4"; ipv4 = "198.51.100.14"; };
        nodePath = [ "access-client" "downstream" "policy" "upstream" "core-wan" ];
      }
      # CONTROL: generic internet destination → not model-owned
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
pass_timed "fs-390-hds-010-sds-010-sms-020:compile" "${start_ms}"

# SMS-020: Shortcut Policy Authorization
# Positive: explicit-service-shortcut with shortcutPolicy=explicit + publicServicePolicy=true
# → must be in shortcutAuthorizations with reason "explicit-public-service-or-ingress-policy"
# Seeded negative 1: no-policy paths to model-owned destinations
# → must NOT be in shortcutAuthorizations
# → must be in broadWanDenials (the model denies them)
# → corresponding diagnostics must exist
# Control: generic internet → must NOT be in shortcutAuthorizations or broadWanDenials

jq -e '
  .enterprise.acme.site.ams.publicIpv4DestinationPolicy as $policy

  # POSITIVE: explicit shortcut is authorized
  | ([ $policy.shortcutAuthorizations[]
       | select(.relationId == "explicit-service-shortcut"
                and .reason == "explicit-public-service-or-ingress-policy"
                and .allowed == true)
     ] | length == 1)

  # SEEDED NEGATIVE 1a: no-policy enterprise-client path NOT authorized
  and ([ $policy.shortcutAuthorizations[]
        | select(.relationId == "no-policy-to-enterprise-client-public")
      ] | length == 0)

  # SEEDED NEGATIVE 1b: no-policy public-ingress path NOT authorized
  and ([ $policy.shortcutAuthorizations[]
        | select(.relationId == "no-policy-to-public-ingress")
      ] | length == 0)

  # SEEDED NEGATIVE 1c: no-policy paths produce diagnostics
  # Each denied path produces one diagnostic with relatedDenial
  and ([ $policy.diagnostics[]
        | select(.relatedDenial != null)
        | .relationId
      ] | sort) == (["no-policy-to-enterprise-client-public",
                     "no-policy-to-public-ingress"] | sort)

  # CONTROL: generic internet neither authorized nor denied
  and ([ $policy.shortcutAuthorizations[]
        | select(.relationId == "ordinary-public-internet")
      ] | length == 0)
  and ([ $policy.broadWanDenials[]
        | select(.relationId == "ordinary-public-internet")
      ] | length == 0)
  and ([ $policy.diagnostics[]
        | select(.relationId == "ordinary-public-internet")
      ] | length == 0)
' "${output_json}" >/dev/null || {
  echo "FAIL fs-390-hds-010-sds-010-sms-020: shortcut policy authorization incorrect" >&2
  jq '.enterprise.acme.site.ams.publicIpv4DestinationPolicy.shortcutAuthorizations' "${output_json}" >&2
  jq '.enterprise.acme.site.ams.publicIpv4DestinationPolicy.diagnostics' "${output_json}" >&2
  exit 1
}

echo "PASS: FS-390-HDS-010-SDS-010-SMS-020 — shortcut authorization verified (positive + seeded negative 1)."
pass_timed "fs-390-hds-010-sds-010-sms-020"
