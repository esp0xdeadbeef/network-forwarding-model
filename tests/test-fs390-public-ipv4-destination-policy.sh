#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-390-HDS-010-SDS-010-SMS-010
# GAMP-ID: FS-390-HDS-010-SDS-010-SMS-020
# GAMP-ID: FS-390-HDS-010-SDS-010-SMS-030
# GAMP-SCOPE: software-module-test

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
pass_timed "fs390-public-ipv4-destination-policy:compile" "${start_ms}"

jq -e '
  .enterprise.acme.site.ams.publicIpv4DestinationPolicy as $policy
  | $policy.destinationClasses["public-ipv4-destination::198.51.100.10"] as $enterpriseClient
  | $policy.destinationClasses["public-ipv4-destination::198.51.100.11"] as $tenantService
  | $policy.destinationClasses["public-ipv4-destination::198.51.100.12"] as $localOwned
  | $policy.destinationClasses["public-ipv4-destination::198.51.100.13"] as $providerOwned
  | $policy.destinationClasses["public-ipv4-destination::198.51.100.14"] as $publicIngress
  | $policy.destinationClasses["public-ipv4-destination::93.184.216.34"] as $genericWan
  | [
      $policy.broadWanDenials[]
      | select(.reason == "broad-wan-does-not-authorize-model-owned-public-ipv4")
      | .relationId
    ] as $deniedRelations
  | [
      $policy.shortcutAuthorizations[]
      | select(.reason == "explicit-public-service-or-ingress-policy")
      | .relationId
    ] as $authorizedRelations
  | ($enterpriseClient.destinationClass == "enterprise-client")
    and ($tenantService.destinationClass == "tenant-service")
    and ($localOwned.destinationClass == "locally-owned-routed")
    and ($providerOwned.destinationClass == "provider-owned")
    and ($publicIngress.destinationClass == "public-ingress")
    and ($genericWan.destinationClass == "generic-wan-internet")
    and ($genericWan.genericWanInternet == true)
    and ($enterpriseClient.modelOwned == true)
    and ($genericWan.modelOwned == false)
    and ($authorizedRelations == [ "explicit-service-shortcut" ])
    and ($deniedRelations | sort) == ([
      "broad-wan-to-enterprise-client-public",
      "broad-wan-to-local-owned-public",
      "broad-wan-to-provider-owned-public",
      "broad-wan-to-public-ingress-owned-public"
    ] | sort)
    and ([ $policy.broadWanDenials[] | select(.relationId == "ordinary-public-internet") ] | length == 0)
    and ([ $policy.broadWanDenials[] | select(.relationId == "explicit-service-shortcut") ] | length == 0)
    and ([ $policy.diagnostics[] | select(.relatedDenial != null) ] | length == 4)
' "${output_json}" >/dev/null || {
  echo "FAIL fs390-public-ipv4-destination-policy: public IPv4 destination policy did not satisfy FS-390 SMS-010/020/030" >&2
  jq '.enterprise.acme.site.ams.publicIpv4DestinationPolicy' "${output_json}" >&2
  exit 1
}

pass_timed "fs390-public-ipv4-destination-policy"
