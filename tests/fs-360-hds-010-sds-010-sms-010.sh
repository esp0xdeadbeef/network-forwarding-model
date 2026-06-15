#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-360-HDS-010-SDS-010-SMS-010
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
              name = "tunneled-gua";
              authorityClass = "tunneled-client-prefix";
              delegatedPrefixLength = 56;
              perTenantPrefixLength = 64;
              sourceFile = "/run/pd/tunneled-gua.prefix";
            }
            {
              allocation = "runtime";
              family = "ipv6";
              name = "provider-owned-gua";
              authorityClass = "provider-owned-client-prefix";
              delegatedPrefixLength = 56;
              perTenantPrefixLength = 64;
              sourceFile = "/run/pd/provider-owned-gua.prefix";
            }
            {
              allocation = "runtime";
              family = "ipv6";
              name = "host-only-upstream";
              authorityClass = "host-only-provider-prefix";
              delegatedPrefixLength = 128;
              perTenantPrefixLength = 128;
              sourceFile = "/run/pd/host-only-upstream.prefix";
            }
            {
              allocation = "runtime";
              family = "ipv6";
              name = "wan-host";
              authorityClass = "wan-address";
              delegatedPrefixLength = 128;
              perTenantPrefixLength = 128;
              sourceFile = "/run/pd/wan-host.prefix";
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
            {
              allocation = "runtime";
              family = "ipv6";
              name = "non-delegating-upstream";
              authorityClass = "non-delegating-upstream-address";
              delegatedPrefixLength = 128;
              perTenantPrefixLength = 128;
              sourceFile = "/run/pd/non-delegating-upstream.prefix";
            }
          ];
        }
      ];
    };

    prefixAuthority.consumerRequests = [
      {
        id = "route-routed-public-ipv4";
        consumer = "route";
        authorityId = "prefix-authority::access-client::4|198.51.100.36/32";
      }
      {
        id = "expose-routed-gua";
        consumer = "exposure";
        authorityId = "prefix-authority::access-client::6|source:/run/pd/routed-gua.prefix";
      }
      {
        id = "assign-delegated-gua";
        consumer = "assignment";
        authorityId = "prefix-authority::access-client::6|source:/run/pd/delegated-gua.prefix";
      }
      {
        id = "route-tunneled-gua";
        consumer = "route";
        authorityId = "prefix-authority::access-client::6|source:/run/pd/tunneled-gua.prefix";
      }
      {
        id = "advertise-provider-owned-gua";
        consumer = "advertisement";
        authorityId = "prefix-authority::access-client::6|source:/run/pd/provider-owned-gua.prefix";
      }
      {
        id = "assign-host-only-upstream";
        consumer = "assignment";
        authorityId = "prefix-authority::access-client::6|source:/run/pd/host-only-upstream.prefix";
      }
      {
        id = "assign-wan-host";
        consumer = "assignment";
        authorityId = "prefix-authority::access-client::6|source:/run/pd/wan-host.prefix";
      }
      {
        id = "assign-uplink-host";
        consumer = "assignment";
        authorityId = "prefix-authority::access-client::6|source:/run/pd/uplink-host.prefix";
      }
      {
        id = "assign-non-delegating-upstream";
        consumer = "assignment";
        authorityId = "prefix-authority::access-client::6|source:/run/pd/non-delegating-upstream.prefix";
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
pass_timed "fs360-downstream-client-public-prefix-authority:compile" "${start_ms}"

jq -e '
  .enterprise.acme.site.ams.prefixAuthority as $pa
  | $pa.records["prefix-authority::access-client::4|198.51.100.36/32"] as $public4
  | $pa.records["prefix-authority::access-client::6|source:/run/pd/routed-gua.prefix"] as $routed
  | $pa.records["prefix-authority::access-client::6|source:/run/pd/delegated-gua.prefix"] as $delegated
  | $pa.records["prefix-authority::access-client::6|source:/run/pd/tunneled-gua.prefix"] as $tunneled
  | $pa.records["prefix-authority::access-client::6|source:/run/pd/provider-owned-gua.prefix"] as $providerOwned
  | $pa.records["prefix-authority::access-client::6|source:/run/pd/host-only-upstream.prefix"] as $hostOnly
  | $pa.records["prefix-authority::access-client::6|source:/run/pd/wan-host.prefix"] as $wan
  | $pa.records["prefix-authority::access-client::6|source:/run/pd/uplink-host.prefix"] as $uplink
  | $pa.records["prefix-authority::access-client::6|source:/run/pd/non-delegating-upstream.prefix"] as $nonDelegating
  | ($public4.authorityClass == "routed-public-ipv4")
    and ($public4.childPurpose == "downstream-client-public-ipv4-routing")
    and ($public4.consumerEligibility.route == true)
    and ($public4.consumerEligibility.exposure == true)
    and ($public4.consumerEligibility.assignment == false)
    and ($routed.authorityClass == "routed-client-prefix")
    and ($routed.childPurpose == "downstream-client-routing")
    and ($routed.consumerEligibility.assignment == true)
    and ($routed.consumerEligibility.exposure == true)
    and ($delegated.authorityClass == "delegated-client-prefix")
    and ($delegated.childPurpose == "downstream-client-delegation")
    and ($delegated.consumerEligibility.assignment == true)
    and ($tunneled.authorityClass == "tunneled-client-prefix")
    and ($tunneled.childPurpose == "downstream-client-tunneled-routing")
    and ($tunneled.consumerEligibility.route == true)
    and ($providerOwned.authorityClass == "provider-owned-client-prefix")
    and ($providerOwned.childPurpose == "downstream-client-provider-owned-routing")
    and ($providerOwned.consumerEligibility.advertisement == true)
    and ($hostOnly.authorityClass == "host-only-provider-prefix")
    and ($hostOnly.childPurpose == "provider-endpoint-host-address")
    and ($hostOnly.consumerEligibility.assignment == false)
    and ($hostOnly.consumerEligibility.exposure == false)
    and ($hostOnly.consumerEligibility.route == true)
    and ($wan.authorityClass == "wan-address")
    and ($wan.childPurpose == "wan-host-address")
    and ($wan.consumerEligibility.assignment == false)
    and ($wan.consumerEligibility.route == false)
    and ($uplink.authorityClass == "uplink-address")
    and ($uplink.childPurpose == "uplink-host-address")
    and ($uplink.consumerEligibility.assignment == false)
    and ($uplink.consumerEligibility.route == false)
    and ($nonDelegating.authorityClass == "non-delegating-upstream-address")
    and ($nonDelegating.childPurpose == "non-delegating-upstream-address")
    and ($nonDelegating.consumerEligibility.assignment == false)
    and ($nonDelegating.consumerEligibility.route == false)
    and ($pa.consumerEligibility["route-routed-public-ipv4"].allowed == true)
    and ($pa.consumerEligibility["expose-routed-gua"].allowed == true)
    and ($pa.consumerEligibility["assign-delegated-gua"].allowed == true)
    and ($pa.consumerEligibility["route-tunneled-gua"].allowed == true)
    and ($pa.consumerEligibility["advertise-provider-owned-gua"].allowed == true)
    and ($pa.deniedSpace["assign-host-only-upstream"].reason == "invalid-consumer-for-authority-class")
    and ($pa.deniedSpace["assign-wan-host"].reason == "invalid-consumer-for-authority-class")
    and ($pa.deniedSpace["assign-uplink-host"].reason == "invalid-consumer-for-authority-class")
    and ($pa.deniedSpace["assign-non-delegating-upstream"].reason == "invalid-consumer-for-authority-class")
' "${output_json}" >/dev/null || {
  echo "FAIL fs360-downstream-client-public-prefix-authority: prefix authority classes did not satisfy FS-360 SMS-010" >&2
  jq '.enterprise.acme.site.ams.prefixAuthority' "${output_json}" >&2
  exit 1
}

pass_timed "fs360-downstream-client-public-prefix-authority"
