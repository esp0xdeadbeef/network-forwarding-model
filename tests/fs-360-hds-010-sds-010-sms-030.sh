#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-360-HDS-010-SDS-010-SMS-030
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
              name = "delegated-gua";
              authorityClass = "delegated-client-prefix";
              delegatedPrefixLength = 56;
              perTenantPrefixLength = 64;
              sourceFile = "/run/pd/delegated-gua.prefix";
            }
          ];
        }
      ];
    };

    prefixAuthority.guaPlacementPreconditions = [
      {
        id = "place-delegated-gua-on-client";
        authorityId = "prefix-authority::access-client::6|source:/run/pd/delegated-gua.prefix";
        family = 6;
        interfaceRole = "access";
        interfaceKind = "client";
      }
      {
        id = "place-delegated-gua-on-policy-transit";
        authorityId = "prefix-authority::access-client::6|source:/run/pd/delegated-gua.prefix";
        family = 6;
        interfaceRole = "policy";
        interfaceKind = "transit";
      }
      {
        id = "place-delegated-gua-on-wan";
        authorityId = "prefix-authority::access-client::6|source:/run/pd/delegated-gua.prefix";
        family = 6;
        interfaceRole = "wan";
        interfaceKind = "wan";
      }
      {
        id = "place-public-ipv4-on-policy-transit";
        authorityId = "prefix-authority::access-client::4|198.51.100.36/32";
        family = 4;
        interfaceRole = "policy";
        interfaceKind = "transit";
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
pass_timed "fs360-gua-transit-placement-validation:compile" "${start_ms}"

jq -e '
  .enterprise.acme.site.ams.prefixAuthority as $pa
  | $pa.guaPlacementPreconditions["place-delegated-gua-on-client"] as $client
  | $pa.guaPlacementPreconditions["place-delegated-gua-on-policy-transit"] as $transit
  | $pa.guaPlacementPreconditions["place-delegated-gua-on-wan"] as $wan
  | $pa.guaPlacementPreconditions["place-public-ipv4-on-policy-transit"] as $ipv4
  | ($client.gampId == "FS-360-HDS-010-SDS-010-SMS-030")
    and ($client.allowed == true)
    and ($client.reason == "allowed")
    and ($client.transitHop == false)
    and ($client.uplinkPlacement == false)
    and ($transit.allowed == false)
    and ($transit.reason == "non-uplink-transit-gua-placement")
    and ($transit.interfaceRole == "policy")
    and ($transit.transitHop == true)
    and ($transit.uplinkPlacement == false)
    and ($wan.allowed == true)
    and ($wan.reason == "allowed")
    and ($wan.transitHop == false)
    and ($wan.uplinkPlacement == true)
    and ($ipv4.allowed == false)
    and ($ipv4.reason == "not-ipv6-gua-placement")
    and ($pa.deniedGuaPlacementPreconditions["place-delegated-gua-on-policy-transit"].reason == "non-uplink-transit-gua-placement")
    and ($pa.deniedGuaPlacementPreconditions["place-public-ipv4-on-policy-transit"].reason == "not-ipv6-gua-placement")
' "${output_json}" >/dev/null || {
  echo "FAIL fs360-gua-transit-placement-validation: SMS-030 GUA placement preconditions missing or incorrect" >&2
  jq '.enterprise.acme.site.ams.prefixAuthority' "${output_json}" >&2
  exit 1
}

pass_timed "fs360-gua-transit-placement-validation"
