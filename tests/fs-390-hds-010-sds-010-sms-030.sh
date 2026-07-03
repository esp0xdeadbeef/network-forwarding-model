#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-390-HDS-010-SDS-010-SMS-030
# GAMP-SCOPE: software-module-test
# Focused construction test: broad WAN public IPv4 denial.
# SMS-030 verifies that broad WAN / public-internet policy does not grant
# shortcut reachability to model-owned public IPv4 destinations by implication.

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
          name = "tenant-service-missing-policy";
          publicIpv4 = "203.0.113.100/32";
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
      {
        relationId = "broad-wan-to-enterprise-client-public";
        action = "allow";
        source = { kind = "tenant"; name = "client"; };
        destination = { kind = "public-ipv4"; ipv4 = "198.51.100.10"; };
        nodePath = [ "access-client" "downstream" "policy" "upstream" "core-wan" ];
      }
      {
        relationId = "explicit-service-shortcut";
        action = "allow";
        source = { kind = "tenant"; name = "client"; };
        destination = { kind = "public-ipv4"; ipv4 = "198.51.100.11"; };
        shortcutPolicy = "explicit";
        publicServicePolicy = true;
        returnBehavior = "symmetric";
        nodePath = [ "access-client" "downstream" "policy" "upstream" "core-wan" ];
      }
      {
        relationId = "broad-wan-to-tenant-service-public";
        action = "allow";
        source = { kind = "tenant"; name = "client"; };
        destination = { kind = "public-ipv4"; ipv4 = "203.0.113.100"; };
        nodePath = [ "access-client" "downstream" "policy" "upstream" "core-wan" ];
      }
      {
        relationId = "broad-wan-to-local-owned-public";
        action = "allow";
        source = { kind = "tenant"; name = "client"; };
        destination = { kind = "public-ipv4"; ipv4 = "198.51.100.12"; };
        nodePath = [ "access-client" "downstream" "policy" "upstream" "core-wan" ];
      }
      {
        relationId = "broad-wan-to-provider-owned-public";
        action = "allow";
        source = { kind = "tenant"; name = "client"; };
        destination = { kind = "public-ipv4"; ipv4 = "198.51.100.13"; };
        nodePath = [ "access-client" "downstream" "policy" "upstream" "core-wan" ];
      }
      {
        relationId = "broad-wan-to-public-ingress-owned-public";
        action = "allow";
        source = { kind = "tenant"; name = "client"; };
        destination = { kind = "public-ipv4"; ipv4 = "198.51.100.14"; };
        nodePath = [ "access-client" "downstream" "policy" "upstream" "core-wan" ];
      }
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
pass_timed "fs-390-hds-010-sds-010-sms-030:compile" "${start_ms}"

jq -e '
  .enterprise.acme.site.ams.publicIpv4DestinationPolicy as $policy
  | [
      "broad-wan-to-enterprise-client-public",
      "broad-wan-to-tenant-service-public",
      "broad-wan-to-local-owned-public",
      "broad-wan-to-provider-owned-public",
      "broad-wan-to-public-ingress-owned-public"
    ] as $deniedRelations

  # SMS-030 positive: every model-owned public IPv4 destination reached only
  # through broad WAN is denied with the broad-WAN reason.
  | ([ $policy.broadWanDenials[]
        | select(.allowed == false
                 and .reason == "broad-wan-does-not-authorize-model-owned-public-ipv4")
        | .relationId
      ] | sort) == ($deniedRelations | sort)

  # Diagnostics name every denied broad-WAN relation.
  and ([ $policy.diagnostics[]
        | select(.relatedDenial != null)
        | .relationId
      ] | sort) == ($deniedRelations | sort)

  # SMS-030 controls: explicit service shortcut is authorized, not denied.
  and ([ $policy.shortcutAuthorizations[]
        | select(.relationId == "explicit-service-shortcut"
                 and .allowed == true
                 and .reason == "explicit-public-service-or-ingress-policy")
      ] | length == 1)
  and ([ $policy.broadWanDenials[]
        | select(.relationId == "explicit-service-shortcut")
      ] | length == 0)

  # Generic public internet remains generic WAN internet, not model-owned denial.
  and ([ $policy.broadWanDenials[]
        | select(.relationId == "ordinary-public-internet")
      ] | length == 0)
' "${output_json}" >/dev/null || {
  echo "FAIL fs-390-hds-010-sds-010-sms-030: broad WAN public IPv4 denial incorrect" >&2
  jq '.enterprise.acme.site.ams.publicIpv4DestinationPolicy.shortcutAuthorizations' "${output_json}" >&2
  jq '.enterprise.acme.site.ams.publicIpv4DestinationPolicy.broadWanDenials' "${output_json}" >&2
  jq '.enterprise.acme.site.ams.publicIpv4DestinationPolicy.diagnostics' "${output_json}" >&2
  exit 1
}

echo "PASS: FS-390-HDS-010-SDS-010-SMS-030 — broad WAN public IPv4 denial verified."
pass_timed "fs-390-hds-010-sds-010-sms-030"
