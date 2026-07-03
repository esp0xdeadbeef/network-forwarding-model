#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-390-HDS-010-SDS-010-SMS-010
# GAMP-SCOPE: software-module-test
# Focused construction test: public IPv4 destination classification.
# SMS-010 verifies that each public IPv4 destination is assigned the correct
# destinationClass based on its source (enterprise-client, tenant-service,
# locally-owned-routed, provider-owned, public-ingress, generic-wan-internet).

repo_root="$(git rev-parse --show-toplevel)"
source "${repo_root}/tests/lib/timing.sh"
tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

input_nix="${tmpdir}/compiler-output.nix"
output_json="${tmpdir}/out.json"
missing_output_json="${tmpdir}/out-missing-classification.json"
ambiguous_input_nix="${tmpdir}/ambiguous-ownership.nix"

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

    ownership = {
      endpoints = [
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
      prefixes = [
        {
          kind = "tenant";
          name = "branch-client";
          ipv4 = "10.39.21.0/24";
          publicIpv4 = "198.51.100.15/32";
        }
      ];
    };

    communicationContract = {
      services = [
        {
          name = "tenant-api";
          publicIpv4 = "198.51.100.11/32";
        }
        {
          name = "fixture-missing-output";
          publicIpv4 = "203.0.113.50/32";
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
pass_timed "fs-390-hds-010-sds-010-sms-010:compile" "${start_ms}"

jq -e '
  .enterprise.acme.site.ams.publicIpv4DestinationPolicy as $policy
  | $policy.destinationClasses["public-ipv4-destination::198.51.100.10"] as $enterpriseClient
  | $policy.destinationClasses["public-ipv4-destination::198.51.100.15"] as $ownershipPrefixEnterpriseClient
  | $policy.destinationClasses["public-ipv4-destination::198.51.100.11"] as $tenantService
  | $policy.destinationClasses["public-ipv4-destination::203.0.113.50"] as $seededTenantService
  | $policy.destinationClasses["public-ipv4-destination::198.51.100.12"] as $localOwned
  | $policy.destinationClasses["public-ipv4-destination::198.51.100.13"] as $providerOwned
  | $policy.destinationClasses["public-ipv4-destination::198.51.100.14"] as $publicIngress
  | $policy.destinationClasses["public-ipv4-destination::93.184.216.34"] as $genericWan
  | ($enterpriseClient.destinationClass == "enterprise-client")
    and ($enterpriseClient.source == "domains.tenants")
    and ($ownershipPrefixEnterpriseClient.destinationClass == "enterprise-client")
    and ($ownershipPrefixEnterpriseClient.ownerName == "branch-client")
    and ($ownershipPrefixEnterpriseClient.source == "ownership.prefixes")
    and ($tenantService.destinationClass == "tenant-service")
    and ($seededTenantService.destinationClass == "tenant-service")
    and ($seededTenantService.ownerName == "fixture-missing-output")
    and ($localOwned.destinationClass == "locally-owned-routed")
    and ($providerOwned.destinationClass == "provider-owned")
    and ($publicIngress.destinationClass == "public-ingress")
    and ($genericWan.destinationClass == "generic-wan-internet")
    and ($genericWan.genericWanInternet == true)
    and ($enterpriseClient.modelOwned == true)
    and ($genericWan.modelOwned == false)
    and ([
      $enterpriseClient,
      $ownershipPrefixEnterpriseClient,
      $tenantService,
      $seededTenantService,
      $localOwned,
      $providerOwned,
      $publicIngress
    ] | all(.modelOwned == true and (.ownerName != null) and (.ownerKind != null) and (.source != null)))
' "${output_json}" >/dev/null || {
  echo "FAIL fs-390-hds-010-sds-010-sms-010: destination classification incorrect" >&2
  jq '.enterprise.acme.site.ams.publicIpv4DestinationPolicy.destinationClasses' "${output_json}" >&2
  exit 1
}

if jq 'del(.enterprise.acme.site.ams.publicIpv4DestinationPolicy.destinationClasses["public-ipv4-destination::203.0.113.50"])' \
  "${output_json}" >"${missing_output_json}"; then
  if jq -e '
    .enterprise.acme.site.ams.publicIpv4DestinationPolicy.destinationClasses["public-ipv4-destination::203.0.113.50"] as $seededTenantService
    | $seededTenantService != null
      and $seededTenantService.destinationClass == "tenant-service"
      and $seededTenantService.ownerName == "fixture-missing-output"
  ' "${missing_output_json}" >/dev/null; then
    echo "FAIL fs-390-hds-010-sds-010-sms-010: seeded missing-output negative did not fail" >&2
    exit 1
  fi
else
  echo "FAIL fs-390-hds-010-sds-010-sms-010: could not seed missing-output negative" >&2
  exit 1
fi

cat >"${ambiguous_input_nix}" <<'NIX'
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
        }
      ];
    };

    communicationContract = {
      services = [
        {
          name = "media-casting";
          publicIpv4 = "198.51.100.10/32";
        }
        {
          name = "ingress-gateway";
          publicIngress = {
            enabled = true;
            ipv4 = "198.51.100.10/32";
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
        relationId = "ambiguous-destination";
        action = "allow";
        source = { kind = "tenant"; name = "client"; };
        destination = { kind = "public-ipv4"; ipv4 = "198.51.100.10"; };
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

if nix run "${repo_root}#compile-and-build-forwarding-model" -- "${ambiguous_input_nix}" >"${tmpdir}/ambiguous.out" 2>"${tmpdir}/ambiguous.err"; then
  echo "FAIL fs-390-hds-010-sds-010-sms-010: ambiguous ownership fixture compiled successfully" >&2
  jq '.enterprise.acme.site.ams.publicIpv4DestinationPolicy.destinationClasses' "${tmpdir}/ambiguous.out" >&2 || true
  exit 1
fi

grep -F "ambiguous-public-ipv4-destination-ownership" "${tmpdir}/ambiguous.err" >/dev/null || {
  echo "FAIL fs-390-hds-010-sds-010-sms-010: ambiguous ownership diagnostic missing" >&2
  cat "${tmpdir}/ambiguous.err" >&2
  exit 1
}

echo "PASS: FS-390-HDS-010-SDS-010-SMS-010 — public IPv4 destination classification verified."
pass_timed "fs-390-hds-010-sds-010-sms-010"
