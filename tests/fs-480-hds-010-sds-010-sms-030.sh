#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-480-HDS-010-SDS-010-SMS-030
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
        id = "deny-overlapping-provider-advertisement";
        gampId = "FS-480-HDS-010-SDS-010-SMS-030";
        authorityId = "prefix-authority::access-client::4|198.51.100.48/32";
        routePrefix = "198.51.100.0/24";
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
        conflictType = "overlap";
        conflictSource = "bgp-provider-b";
      }
      {
        id = "deny-unauthorized-source-provider";
        gampId = "FS-480-HDS-010-SDS-010-SMS-030";
        authorityId = "prefix-authority::access-client::4|198.51.100.48/32";
        routePrefix = "198.51.100.48/32";
        allowedPrefixes = [ "198.51.100.48/32" ];
        sourcePeerOrProvider = "bgp-provider-b";
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
    ];

    communicationContract.relations = [
      {
        id = "allow-client-to-wan";
        priority = 100;
        from = { kind = "tenant"; name = "client"; };
        to = { kind = "external"; uplinks = [ "wan" ]; };
        trafficType = "any";
        action = "allow";
        returnBehavior = "symmetric";
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
pass_timed "fs480-route-import-advertisement-denial:compile" "${start_ms}"

jq -e '
  .enterprise.acme.site.ams.prefixAuthority as $pa
  | $pa.deniedRouteImportConstraints["deny-overlapping-provider-advertisement"] as $overlap
  | $pa.deniedRouteImportConstraints["deny-unauthorized-source-provider"] as $sourceDenied
  | ($pa.routeImportConstraints["deny-overlapping-provider-advertisement"].allowed == false)
    and ($overlap.allowed == false)
    and ($overlap.gampId == "FS-480-HDS-010-SDS-010-SMS-030")
    and ($overlap.reason == "route-prefix-not-allowed")
    and ($overlap.diagnosticCode == "OVERLAPPING_ROUTE_ADVERTISEMENT")
    and ($overlap.reachabilityClassification == "denied")
    and ($overlap.diagnostic.conflictType == "overlap")
    and ($overlap.diagnostic.conflictSource == "bgp-provider-b")
    and ($overlap.diagnostic.routePrefix == "198.51.100.0/24")
    and ($pa.routeImportConstraints["deny-unauthorized-source-provider"].allowed == false)
    and ($sourceDenied.allowed == false)
    and ($sourceDenied.gampId == "FS-480-HDS-010-SDS-010-SMS-030")
    and ($sourceDenied.reason == "unexpected-source-peer-or-provider")
    and ($sourceDenied.diagnosticCode == "UNAUTHORIZED_ROUTE_SOURCE")
    and ($sourceDenied.reachabilityClassification == "denied")
    and ($sourceDenied.sourcePeerOrProvider == "bgp-provider-b")
    and ($sourceDenied.allowedSources == ["bgp-provider-a"])
    and ($sourceDenied.diagnostic.sourcePeerOrProvider == "bgp-provider-b")
' "${output_json}" >/dev/null || {
  echo "FAIL fs480-route-import-advertisement-denial: overlapping or unauthorized advertisement was not rejected with a named source" >&2
  jq '.enterprise.acme.site.ams.prefixAuthority' "${output_json}" >&2
  exit 1
}

pass_timed "fs480-route-import-advertisement-denial"
