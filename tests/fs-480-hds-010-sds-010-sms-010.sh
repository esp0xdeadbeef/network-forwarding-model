#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-480-HDS-010-SDS-010-SMS-010
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
        id = "explicit-authority-owned-service-import";
        gampId = "FS-480-HDS-010-SDS-010-SMS-010";
        authorityId = "prefix-authority::access-client::4|198.51.100.48/32";
        routePrefix = "198.51.100.48/32";
        allowedPrefixes = [ "198.51.100.48/32" ];
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
      }
      {
        id = "bgp-learned-owned-service-without-authority";
        gampId = "FS-480-HDS-010-SDS-010-SMS-010";
        authorityId = "prefix-authority::missing::4|198.51.100.49/32";
        routePrefix = "198.51.100.49/32";
        allowedPrefixes = [ "198.51.100.49/32" ];
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
      }
      {
        id = "provider-default-route-without-authority";
        gampId = "FS-480-HDS-010-SDS-010-SMS-010";
        authorityId = "prefix-authority::missing::4|0.0.0.0/0";
        routePrefix = "0.0.0.0/0";
        allowedPrefixes = [ "0.0.0.0/0" ];
        sourcePeerOrProvider = "bgp-provider-a";
        allowedSources = [ "bgp-provider-a" ];
        routePurpose = "wan-internet";
        allowedPurposes = [ "wan-internet" ];
        destinationOwner = "provider-a";
        allowedDestinationOwners = [ "provider-a" ];
        maximumScope = "provider";
        routeScope = "provider";
        exportRequested = false;
        exportEligible = false;
        rejectionBehavior = "reject";
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
pass_timed "fs480-runtime-route-import-authority:compile" "${start_ms}"

jq -e '
  .enterprise.acme.site.ams.prefixAuthority as $pa
  | $pa.routeImportConstraints["explicit-authority-owned-service-import"] as $allow
  | $pa.deniedRouteImportConstraints["bgp-learned-owned-service-without-authority"] as $missingOwned
  | $pa.deniedRouteImportConstraints["provider-default-route-without-authority"] as $missingDefault
  | ($allow.gampId == "FS-480-HDS-010-SDS-010-SMS-010")
    and ($allow.allowed == true)
    and ($allow.authorityClass == "routed-public-ipv4")
    and ($allow.routePrefix == "198.51.100.48/32")
    and ($allow.sourcePeerOrProvider == "bgp-provider-a")
    and ($allow.routePurpose == "owned-public-service-prefix")
    and ($allow.destinationOwner == "access-client")
    and ($allow.diagnostic == null)
    and ($allow.diagnosticCode == null)
    and ($allow.reachabilityClassification == "allowed")
    and ($pa.routeImportConstraints["bgp-learned-owned-service-without-authority"].allowed == false)
    and ($missingOwned.allowed == false)
    and ($missingOwned.gampId == "FS-480-HDS-010-SDS-010-SMS-010")
    and ($missingOwned.diagnosticCode == "MISSING_ROUTE_IMPORT_AUTHORITY")
    and ($missingOwned.reachabilityClassification == "ambiguous")
    and ($missingOwned.diagnostic.code == "MISSING_ROUTE_IMPORT_AUTHORITY")
    and ($missingOwned.diagnostic.routePrefix == "198.51.100.49/32")
    and ($missingOwned.diagnostic.sourcePeerOrProvider == "bgp-provider-a")
    and ($missingOwned.diagnostic.routePurpose == "owned-public-service-prefix")
    and ($pa.routeImportConstraints["provider-default-route-without-authority"].allowed == false)
    and ($missingDefault.allowed == false)
    and ($missingDefault.gampId == "FS-480-HDS-010-SDS-010-SMS-010")
    and ($missingDefault.diagnosticCode == "MISSING_ROUTE_IMPORT_AUTHORITY")
    and ($missingDefault.reachabilityClassification == "ambiguous")
    and ($missingDefault.diagnostic.routePrefix == "0.0.0.0/0")
    and ($missingDefault.diagnostic.routePurpose == "wan-internet")
' "${output_json}" >/dev/null || {
  echo "FAIL fs480-runtime-route-import-authority: learned routes were accepted without explicit import authority" >&2
  jq '.enterprise.acme.site.ams.prefixAuthority' "${output_json}" >&2
  exit 1
}

pass_timed "fs480-runtime-route-import-authority"
