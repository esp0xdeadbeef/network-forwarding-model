#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-370-HDS-010-SDS-010-SMS-030
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
      local.ipv4 = "10.37.0.0/24";
      p2p.ipv4 = "10.37.1.0/24";
      p2p.ipv6 = "fd42:370::/118";
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
          ipv4 = "10.37.20.0/24";
          ipv6 = "fd42:370:20::/64";
          routedPrefixes = [
            {
              allocation = "runtime";
              family = "ipv4";
              name = "client-host-only-v4";
              delegatedPrefixLength = 32;
              perTenantPrefixLength = 32;
              slot = 0;
              sourceFile = "/run/pd/client-host-only-v4.prefix";
            }
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
pass_timed "fs370-host-only-source-prefix-denial:compile" "${start_ms}"

jq -e '
  .enterprise.acme.site.ams as $site
  | $site.tenantPrefixOwners["4|source:/run/pd/client-host-only-v4.prefix"] as $hostOnlyV4Owner
  | $site.tenantPrefixOwners["6|source:/run/pd/client-host-only.prefix"] as $hostOnlyV6Owner
  | $site.prefixAuthority.records["prefix-authority::access-client::4|source:/run/pd/client-host-only-v4.prefix"] as $hostOnlyV4Authority
  | $site.prefixAuthority.records["prefix-authority::access-client::6|source:/run/pd/client-host-only.prefix"] as $hostOnlyV6Authority
  | def host_only_v4_routes:
      $site.nodes
      | to_entries[]
      | . as $node
      | ($node.value.interfaces // {})
      | to_entries[]
      | (.value.routes.ipv4 // [])[]?
      | { node: $node.key, route: . }
      | select((.route.sourceFile // null) == "/run/pd/client-host-only-v4.prefix");
  def host_only_v6_routes:
      $site.nodes
      | to_entries[]
      | . as $node
      | ($node.value.interfaces // {})
      | to_entries[]
      | (.value.routes.ipv6 // [])[]?
      | { node: $node.key, route: . }
      | select((.route.sourceFile // null) == "/run/pd/client-host-only.prefix");
  ($hostOnlyV4Owner.owner == "access-client")
  and ($hostOnlyV4Owner.authorityClass == "host-only-provider-prefix")
  and ($hostOnlyV4Authority.authorityClass == "host-only-provider-prefix")
  and ($hostOnlyV4Authority.childPurpose == "provider-endpoint-host-address")
  and ($hostOnlyV4Authority.consumerEligibility.route == true)
  and ($hostOnlyV4Authority.consumerEligibility.assignment == false)
  and ($hostOnlyV4Authority.consumerEligibility.exposure == false)
  and ([host_only_v4_routes.node] | sort) == ["core-wan", "downstream", "policy", "upstream"]
  and all(host_only_v4_routes;
    .route.intent.kind == "runtime-routed-prefix-return"
    and .route.intent.accessNode == "access-client"
    and .route.intent.authorityClass == "host-only-provider-prefix"
    and .route.intent.downstreamExport.allowed == false
    and .route.intent.downstreamExport.reason == "host-only-provider-prefix"
  )
  and ($hostOnlyV6Owner.owner == "access-client")
  and ($hostOnlyV6Owner.authorityClass == "host-only-provider-prefix")
  and ($hostOnlyV6Authority.authorityClass == "host-only-provider-prefix")
  and ($hostOnlyV6Authority.childPurpose == "provider-endpoint-host-address")
  and ($hostOnlyV6Authority.consumerEligibility.route == true)
  and ($hostOnlyV6Authority.consumerEligibility.assignment == false)
  and ($hostOnlyV6Authority.consumerEligibility.exposure == false)
  and ([host_only_v6_routes.node] | sort) == ["core-wan", "downstream", "policy", "upstream"]
  and all(host_only_v6_routes;
    .route.intent.kind == "runtime-routed-prefix-return"
    and .route.intent.accessNode == "access-client"
    and .route.intent.authorityClass == "host-only-provider-prefix"
    and .route.intent.downstreamExport.allowed == false
    and .route.intent.downstreamExport.reason == "host-only-provider-prefix"
  )
' "${output_json}" >/dev/null || {
  echo "FAIL fs370-host-only-source-prefix-denial: NFM must preserve host-only authority and mark downstream export denied before CPM" >&2
  jq '.enterprise.acme.site.ams | {
    tenantPrefixOwners,
    prefixAuthority,
    routes: [
      .nodes
      | to_entries[]
      | . as $node
      | ($node.value.interfaces // {})
      | to_entries[]
      | (.value.routes.ipv6 // [])[]?
      | select(
          (.sourceFile // null) == "/run/pd/client-host-only-v4.prefix"
          or (.sourceFile // null) == "/run/pd/client-host-only.prefix"
        )
      | { node: $node.key, route: . }
    ]
  }' "${output_json}" >&2
  exit 1
}

pass_timed "fs370-host-only-source-prefix-denial"
