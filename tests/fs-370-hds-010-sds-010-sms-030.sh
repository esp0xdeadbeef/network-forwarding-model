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
pass_timed "fs370-host-only-source-prefix-denial:compile" "${start_ms}"

jq -e '
  .enterprise.acme.site.ams as $site
  | $site.tenantPrefixOwners["6|source:/run/pd/client-host-only.prefix"] as $hostOnlyOwner
  | $site.prefixAuthority.records["prefix-authority::access-client::6|source:/run/pd/client-host-only.prefix"] as $hostOnlyAuthority
  | def host_only_routes:
      $site.nodes
      | to_entries[]
      | . as $node
      | ($node.value.interfaces // {})
      | to_entries[]
      | (.value.routes.ipv6 // [])[]?
      | { node: $node.key, route: . }
      | select((.route.sourceFile // null) == "/run/pd/client-host-only.prefix");
  ($hostOnlyOwner.owner == "access-client")
  and ($hostOnlyOwner.authorityClass == "host-only-provider-prefix")
  and ($hostOnlyAuthority.authorityClass == "host-only-provider-prefix")
  and ($hostOnlyAuthority.childPurpose == "provider-endpoint-host-address")
  and ($hostOnlyAuthority.consumerEligibility.route == true)
  and ($hostOnlyAuthority.consumerEligibility.assignment == false)
  and ($hostOnlyAuthority.consumerEligibility.exposure == false)
  and ([host_only_routes.node] | sort) == ["core-wan", "downstream", "policy", "upstream"]
  and all(host_only_routes;
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
      | select((.sourceFile // null) == "/run/pd/client-host-only.prefix")
      | { node: $node.key, route: . }
    ]
  }' "${output_json}" >&2
  exit 1
}

pass_timed "fs370-host-only-source-prefix-denial"
