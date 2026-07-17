#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: SMT-NFM-FS350-PREFIX-AUTHORITY-001
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
      local.ipv4 = "10.0.0.0/24";
      p2p.ipv4 = "10.0.1.0/24";
      p2p.ipv6 = "fd42:0:0:1000::/118";
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
          ipv4 = "10.10.0.0/24";
          ipv6 = "fd42:10:a::/64";
          routedPrefixes = [
            {
              allocation = "runtime";
              family = "ipv6";
              name = "client-public";
              delegatedPrefixLength = 56;
              perTenantPrefixLength = 64;
              slot = 1;
              sourceFile = "/run/pd/client.prefix";
            }
          ];
        }
      ];
    };

    prefixAuthority = {
      reservations = [
        {
          id = "reserved-doc";
          family = 6;
          prefix = "2001:db8:350:bad::/64";
          authorityClass = "reserved-space";
          reservationState = "reserved";
          scopeKind = "site";
          scopeName = "ams";
        }
      ];
      consumerRequests = [
        {
          id = "assign-client-v4";
          consumer = "assignment";
          authorityId = "prefix-authority::access-client::4|10.10.0.0/24";
        }
        {
          id = "route-runtime-gua";
          consumer = "route";
          authorityId = "prefix-authority::access-client::6|source:/run/pd/client.prefix";
        }
        {
          id = "translate-access-v4";
          consumer = "translation";
          authorityId = "prefix-authority::access-client::4|10.10.0.0/24";
        }
        {
          id = "consume-reserved";
          consumer = "assignment";
          authorityId = "prefix-reservation::reserved-doc";
        }
        {
          id = "consume-unassigned";
          consumer = "route";
          family = 6;
          prefix = "2001:db8:350:missing::/64";
        }
      ];
    };

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
pass_timed "fs350-prefix-authority-consumer-eligibility:compile" "${start_ms}"

jq -e '
  .enterprise.acme.site.ams.prefixAuthority as $pa
  | $pa.records["prefix-authority::access-client::4|10.10.0.0/24"] as $access4
  | $pa.records["prefix-authority::access-client::6|source:/run/pd/client.prefix"] as $runtime6
  | $pa.records["prefix-reservation::reserved-doc"] as $reserved
  | $pa.consumerEligibility["assign-client-v4"] as $assign
  | $pa.consumerEligibility["route-runtime-gua"] as $routeRuntime
  | $pa.deniedSpace["translate-access-v4"] as $wrongClass
  | $pa.deniedSpace["consume-reserved"] as $reservedDenied
  | $pa.deniedSpace["consume-unassigned"] as $unassignedDenied
  | ($access4.authorityClass == "access-subnet-pool")
    and ($access4.sourceAuthority.kind == "modeled-prefix")
    and ($access4.sourceAuthority.prefix == "10.10.0.0/24")
    and ($access4.childPurpose == "tenant-or-access-assignment")
    and ($runtime6.authorityClass == "routed-client-prefix")
    and ($runtime6.sourceAuthority.kind == "modeled-runtime-routed-prefix")
    and ($runtime6.sourceAuthority.sourceFile == "/run/pd/client.prefix")
    and ($runtime6.childPurpose == "downstream-client-routing")
    and ($reserved.reservationState == "reserved")
    and ($reserved.consumerEligibility.assignment == false)
    and ($assign.allowed == true)
    and ($routeRuntime.allowed == true)
    and ($wrongClass.allowed == false)
    and ($wrongClass.reason == "invalid-consumer-for-authority-class")
    and ($reservedDenied.allowed == false)
    and ($reservedDenied.reason == "reserved-prefix-authority")
    and ($unassignedDenied.allowed == false)
    and ($unassignedDenied.reason == "unassigned-prefix-authority")
' "${output_json}" >/dev/null || {
  echo "FAIL fs350-prefix-authority-consumer-eligibility: prefix authority records did not satisfy FS-350 SMS-010/020/040" >&2
  jq '.enterprise.acme.site.ams.prefixAuthority' "${output_json}" >&2
  exit 1
}

pass_timed "fs350-prefix-authority-consumer-eligibility"
