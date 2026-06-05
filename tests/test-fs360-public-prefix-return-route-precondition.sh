#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-360-HDS-010-SDS-010-SMS-020
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
      local.ipv4 = "10.36.0.0/24";
      p2p.ipv4 = "10.36.1.0/24";
      p2p.ipv6 = "fd42:360::/118";
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
          ipv4 = "10.36.20.0/24";
          ipv6 = "fd42:360:20::/64";
          publicIpv4 = "198.51.100.36/32";
          routedPrefixes = [
            {
              allocation = "runtime";
              family = "ipv6";
              name = "routed-gua";
              authorityClass = "routed-client-prefix";
              delegatedPrefixLength = 56;
              perTenantPrefixLength = 64;
              sourceFile = "/run/pd/routed-gua.prefix";
            }
            {
              allocation = "runtime";
              family = "ipv6";
              name = "delegated-gua";
              authorityClass = "delegated-client-prefix";
              delegatedPrefixLength = 56;
              perTenantPrefixLength = 64;
              sourceFile = "/run/pd/delegated-gua.prefix";
            }
            {
              allocation = "runtime";
              family = "ipv6";
              name = "uplink-host";
              authorityClass = "uplink-address";
              delegatedPrefixLength = 128;
              perTenantPrefixLength = 128;
              sourceFile = "/run/pd/uplink-host.prefix";
            }
          ];
        }
      ];
    };

    prefixAuthority.routeExportPreconditions = [
      {
        id = "route-routed-gua-with-return";
        consumer = "route";
        authorityId = "prefix-authority::access-client::6|source:/run/pd/routed-gua.prefix";
        returnRoute = {
          id = "return-route::wan::client";
          via = "core-wan";
          interface = "wan-core-wan-wan";
        };
      }
      {
        id = "assign-delegated-gua-missing-return";
        consumer = "assignment";
        authorityId = "prefix-authority::access-client::6|source:/run/pd/delegated-gua.prefix";
      }
      {
        id = "assign-uplink-host-with-return";
        consumer = "assignment";
        authorityId = "prefix-authority::access-client::6|source:/run/pd/uplink-host.prefix";
        returnRoute = {
          id = "return-route::wan::client";
          via = "core-wan";
          interface = "wan-core-wan-wan";
        };
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
pass_timed "fs360-public-prefix-return-route-precondition:compile" "${start_ms}"

jq -e '
  .enterprise.acme.site.ams.prefixAuthority as $pa
  | $pa.routeExportPreconditions["route-routed-gua-with-return"] as $allowed
  | $pa.routeExportPreconditions["assign-delegated-gua-missing-return"] as $missing
  | $pa.routeExportPreconditions["assign-uplink-host-with-return"] as $invalid
  | ($allowed.gampId == "FS-360-HDS-010-SDS-010-SMS-020")
    and ($allowed.allowed == true)
    and ($allowed.reason == "allowed")
    and ($allowed.returnRouteModeled == true)
    and ($allowed.authorityClass == "routed-client-prefix")
    and ($missing.allowed == false)
    and ($missing.reason == "missing-modeled-return-route")
    and ($missing.returnRouteModeled == false)
    and ($missing.authorityClass == "delegated-client-prefix")
    and ($invalid.allowed == false)
    and ($invalid.reason == "invalid-consumer-for-authority-class")
    and ($invalid.authorityClass == "uplink-address")
    and ($pa.deniedRouteExportPreconditions["assign-delegated-gua-missing-return"].reason == "missing-modeled-return-route")
    and ($pa.deniedRouteExportPreconditions["assign-uplink-host-with-return"].reason == "invalid-consumer-for-authority-class")
' "${output_json}" >/dev/null || {
  echo "FAIL fs360-public-prefix-return-route-precondition: SMS-020 return-route preconditions missing or incorrect" >&2
  jq '.enterprise.acme.site.ams.prefixAuthority' "${output_json}" >&2
  exit 1
}

pass_timed "fs360-public-prefix-return-route-precondition"
