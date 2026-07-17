#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-480-HDS-010-SDS-010-SMS-020
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
        id = "allow-owned-public-import";
        authorityId = "prefix-authority::access-client::4|198.51.100.48/32";
        routePrefix = "198.51.100.48/32";
        allowedPrefixes = [ "198.51.100.48/32" ];
        sourcePeerOrProvider = "provider-a";
        allowedSources = [ "provider-a" ];
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
        id = "deny-scope-overflow";
        authorityId = "prefix-authority::access-client::4|198.51.100.48/32";
        routePrefix = "198.51.100.48/32";
        allowedPrefixes = [ "198.51.100.48/32" ];
        sourcePeerOrProvider = "provider-a";
        allowedSources = [ "provider-a" ];
        routePurpose = "owned-public-service-prefix";
        allowedPurposes = [ "owned-public-service-prefix" ];
        destinationOwner = "access-client";
        allowedDestinationOwners = [ "access-client" ];
        maximumScope = "site";
        routeScope = "provider";
        exportRequested = false;
        exportEligible = true;
        rejectionBehavior = "reject";
      }
      {
        id = "deny-unauthorized-export";
        authorityId = "prefix-authority::access-client::4|198.51.100.48/32";
        routePrefix = "198.51.100.48/32";
        allowedPrefixes = [ "198.51.100.48/32" ];
        sourcePeerOrProvider = "provider-a";
        allowedSources = [ "provider-a" ];
        routePurpose = "owned-public-service-prefix";
        allowedPurposes = [ "owned-public-service-prefix" ];
        destinationOwner = "access-client";
        allowedDestinationOwners = [ "access-client" ];
        maximumScope = "site";
        routeScope = "site";
        exportRequested = true;
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
pass_timed "fs480-route-import-constraint-validation:compile" "${start_ms}"

jq -e '
  .enterprise.acme.site.ams.prefixAuthority as $pa
  | $pa.routeImportConstraints["allow-owned-public-import"] as $allow
  | $pa.deniedRouteImportConstraints["deny-scope-overflow"] as $scopeDenied
  | $pa.deniedRouteImportConstraints["deny-unauthorized-export"] as $exportDenied
  | ($allow.gampId == "FS-480-HDS-010-SDS-010-SMS-020")
    and ($allow.allowed == true)
    and ($allow.authorityClass == "routed-public-ipv4")
    and ($allow.authorityOwner == "access-client")
    and ($allow.routePrefix == "198.51.100.48/32")
    and ($allow.allowedPrefixes == ["198.51.100.48/32"])
    and ($allow.sourcePeerOrProvider == "provider-a")
    and ($allow.allowedSources == ["provider-a"])
    and ($allow.routePurpose == "owned-public-service-prefix")
    and ($allow.allowedPurposes == ["owned-public-service-prefix"])
    and ($allow.destinationOwner == "access-client")
    and ($allow.allowedDestinationOwners == ["access-client"])
    and ($allow.maximumScope == "site")
    and ($allow.routeScope == "site")
    and ($allow.exportRequested == true)
    and ($allow.exportEligible == true)
    and ($allow.rejectionBehavior == "reject")
    and ($allow.diagnostic == null)
    and ($allow.diagnosticCode == null)
    and ($allow.reachabilityClassification == "allowed")
    and ($scopeDenied.allowed == false)
    and ($scopeDenied.reason == "maximum-scope-exceeded")
    and ($scopeDenied.diagnosticCode == "ROUTE_IMPORT_SCOPE_EXCEEDED")
    and ($scopeDenied.reachabilityClassification == "denied")
    and ($scopeDenied.routeScope == "provider")
    and ($scopeDenied.maximumScope == "site")
    and ($exportDenied.allowed == false)
    and ($exportDenied.reason == "unauthorized-export")
    and ($exportDenied.diagnosticCode == "UNAUTHORIZED_ROUTE_EXPORT")
    and ($exportDenied.reachabilityClassification == "denied")
    and ($exportDenied.exportRequested == true)
    and ($exportDenied.exportEligible == false)
' "${output_json}" >/dev/null || {
  echo "FAIL fs480-route-import-constraint-validation: route-import constraints did not satisfy FS-480 SMS-020" >&2
  jq '.enterprise.acme.site.ams.prefixAuthority' "${output_json}" >&2
  exit 1
}

pass_timed "fs480-route-import-constraint-validation"
