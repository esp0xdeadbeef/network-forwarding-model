#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-380-HDS-010-SDS-010-SMS-010
# GAMP-SCOPE: software-module-test
# Focused construction test: NFM route authority handoff for public IPv4.
# SMS-010 verifies that public IPv4 prefix authority records survive through
# NFM forwarding model with correct consumer eligibility and route metadata.

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
      local.ipv4 = "10.38.0.0/24";
      p2p.ipv4 = "10.38.1.0/24";
      p2p.ipv6 = "fd42:380::/118";
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
          ipv4 = "10.38.20.0/24";
          ipv6 = "fd42:380:20::/64";
          publicIpv4 = "198.51.100.38/32";
          routedPrefixes = [
            {
              allocation = "runtime";
              family = "ipv6";
              name = "client-host-only";
              delegatedPrefixLength = 128;
              perTenantPrefixLength = 128;
              slot = 0;
              sourceFile = "/run/pd/client-host-only.prefix";
            }
          ];
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
pass_timed "fs-380-hds-010-sds-010-sms-010:compile" "${start_ms}"

jq -e '
  .enterprise.acme.site.ams as $site
  | $site.tenantPrefixOwners["4|198.51.100.38/32"] as $publicOwner
  | $site.prefixAuthority.records["prefix-authority::access-client::4|198.51.100.38/32"] as $publicAuthority
  | def routes:
      $site.nodes
      | to_entries[]
      | . as $node
      | ($node.value.interfaces // {})
      | to_entries[]
      | (.value.routes.ipv4 // [])[]?, (.value.routes.ipv6 // [])[]?
      | { node: $node.key, route: . };
    def public_routes:
      routes
      | select(
          .route.dst == "198.51.100.38/32"
          and .route.intent.kind == "routed-public-ipv4-return"
        );
    ($publicOwner.owner == "access-client")
    and ($publicOwner.kind == "routed-public-ipv4")
    and ($publicOwner.authorityClass == "routed-public-ipv4")
    and ($publicOwner.source == "domains.tenants.publicIpv4")
    and ($publicAuthority.authorityClass == "routed-public-ipv4")
    and ($publicAuthority.sourceAuthority.prefix == "198.51.100.38/32")
    and ($publicAuthority.sourceAuthority.source == "domains.tenants.publicIpv4")
    and ($publicAuthority.consumerEligibility.route == true)
    and ($publicAuthority.consumerEligibility.exposure == true)
    and ([public_routes.node] | sort) == ["core-wan", "downstream", "policy", "upstream"]
    and all(public_routes;
      .route.intent.accessNode == "access-client"
      and .route.intent.authorityClass == "routed-public-ipv4"
      and .route.intent.source == "domains.tenants.publicIpv4"
      and .route.intent.downstreamExport.allowed == true
    )
' "${output_json}" >/dev/null || {
  echo "FAIL fs-380-hds-010-sds-010-sms-010: public IPv4 route authority did not survive into forwarding output" >&2
  jq '.enterprise.acme.site.ams | {
    tenantPrefixOwners,
    prefixAuthority,
    routes: [
      .nodes
      | to_entries[]
      | . as $node
      | ($node.value.interfaces // {})
      | to_entries[]
      | (.value.routes.ipv4 // [])[]?, (.value.routes.ipv6 // [])[]?
      | select(.dst == "198.51.100.38/32")
      | { node: $node.key, route: . }
    ]
  }' "${output_json}" >&2
  exit 1
}

echo "PASS: FS-380-HDS-010-SDS-010-SMS-010 — public IPv4 route authority verified."
pass_timed "fs-380-hds-010-sds-010-sms-010"
