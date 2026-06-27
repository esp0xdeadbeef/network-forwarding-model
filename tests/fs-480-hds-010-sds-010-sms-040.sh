#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-480-HDS-010-SDS-010-SMS-040
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
      local.ipv4 = "10.48.0.0/24";
      p2p.ipv4 = "10.48.1.0/24";
      p2p.ipv6 = "fd42:480::/118";
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
          ipv4 = "10.48.20.0/24";
          ipv6 = "fd42:480:20::/64";
          publicIpv4 = "198.51.100.48/32";
        }
      ];
    };

    prefixAuthority.routeImportConstraints = [
      {
        id = "explain-missing-route-import-authority";
        gampId = "FS-480-HDS-010-SDS-010-SMS-040";
        authorityId = "prefix-authority::missing::4|203.0.113.40/32";
        routePrefix = "203.0.113.40/32";
        allowedPrefixes = [ "203.0.113.40/32" ];
        sourcePeerOrProvider = "bgp-provider-a";
        allowedSources = [ "bgp-provider-a" ];
        routePurpose = "provider-prefix";
        allowedPurposes = [ "provider-prefix" ];
        destinationOwner = "provider-a";
        allowedDestinationOwners = [ "provider-a" ];
        maximumScope = "provider";
        routeScope = "provider";
        exportRequested = false;
        exportEligible = false;
        rejectionBehavior = "reject";
      }
      {
        id = "reject-authority-free-allowed-downgrade";
        gampId = "FS-480-HDS-010-SDS-010-SMS-040";
        authorityId = "prefix-authority::missing::4|198.51.100.50/32";
        routePrefix = "198.51.100.50/32";
        allowedPrefixes = [ "198.51.100.50/32" ];
        sourcePeerOrProvider = "bgp-provider-a";
        allowedSources = [ "bgp-provider-a" ];
        routePurpose = "owned-public-service-prefix";
        allowedPurposes = [ "owned-public-service-prefix" ];
        destinationOwner = "access-client";
        allowedDestinationOwners = [ "access-client" ];
        maximumScope = "site";
        routeScope = "site";
        exportRequested = true;
        exportEligible = true;
        rejectionBehavior = "reject";
        authorityFreeRouteAsAllowed = true;
      }
    ];

    communicationContract.relations = [
      {
        id = "allow-client-to-wan";
        priority = 100;
        from = { kind = "tenant"; name = "client"; };
        to = { kind = "external"; uplinks = [ "wan" ]; };
        trafficType = "any";
        action = "allow";
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
        uplinks.wan.ipv6 = [ "::/0" ];
      };
    };
  };
}
NIX

start_ms="$(test_now_ms)"
nix run "${repo_root}#compile-and-build-forwarding-model" -- "${input_nix}" >"${output_json}"
pass_timed "fs480-missing-route-import-authority-explanation:compile" "${start_ms}"

jq -e '
  .enterprise.acme.site.ams.prefixAuthority as $pa
  | $pa.deniedRouteImportConstraints["explain-missing-route-import-authority"] as $missing
  | $pa.deniedRouteImportConstraints["reject-authority-free-allowed-downgrade"] as $downgrade
  | ($pa.routeImportConstraints["explain-missing-route-import-authority"].allowed == false)
    and ($missing.allowed == false)
    and ($missing.gampId == "FS-480-HDS-010-SDS-010-SMS-040")
    and ($missing.diagnosticCode == "MISSING_ROUTE_IMPORT_AUTHORITY")
    and ($missing.reachabilityClassification == "ambiguous")
    and ($missing.diagnostic.routePrefix == "203.0.113.40/32")
    and ($missing.diagnostic.sourcePeerOrProvider == "bgp-provider-a")
    and ($missing.diagnostic.routePurpose == "provider-prefix")
    and ($missing.diagnostic.destinationOwner == "provider-a")
    and ($pa.routeImportConstraints["reject-authority-free-allowed-downgrade"].allowed == false)
    and ($downgrade.allowed == false)
    and ($downgrade.gampId == "FS-480-HDS-010-SDS-010-SMS-040")
    and ($downgrade.diagnosticCode == "AUTHORITY_FREE_ROUTE_AS_ALLOWED")
    and ($downgrade.reachabilityClassification == "ambiguous")
    and ($downgrade.diagnostic.routePrefix == "198.51.100.50/32")
    and ($downgrade.diagnostic.destinationOwner == "access-client")
' "${output_json}" >/dev/null || {
  echo "FAIL fs480-missing-route-import-authority-explanation: missing route authority was not preserved as an explicit ambiguous diagnostic" >&2
  jq '.enterprise.acme.site.ams.prefixAuthority' "${output_json}" >&2
  exit 1
}

pass_timed "fs480-missing-route-import-authority-explanation"
