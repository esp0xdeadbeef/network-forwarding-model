#!/usr/bin/env bash
set -euo pipefail

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
              sourceFile = "/run/s88-ipv6-pd/wan.prefix";
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

nix run "${repo_root}#compile-and-build-forwarding-model" -- "${input_nix}" >"${output_json}"

jq -e '
  .enterprise.acme.site.ams as $site
  | def source: "/run/s88-ipv6-pd/wan.prefix";
    def source_routes:
      $site.nodes
      | to_entries[]
      | . as $node
      | ($node.value.interfaces // {})
      | to_entries[]
      | (.value.routes.ipv6 // [])[]
      | select((.sourceFile // null) == source)
      | {
          node: $node.key,
          proto,
          kind: .intent.kind,
          sourceFile,
          via: (.via // .via6 // null)
        };
    def p2p_gua_addresses:
      $site.nodes
      | to_entries[]
      | . as $node
      | ($node.value.interfaces // {})
      | to_entries[]
      | select((.value.kind // "") == "p2p")
      | (.value.addr6 // .value.ipv6 // "") as $addr
      | select($addr != "" and ($addr | startswith("fd") | not))
      | { node: $node.key, interface: .key, addr6: $addr };
    ([source_routes.node] | sort) == ["core-wan", "downstream", "policy", "upstream"]
    and all(source_routes; .proto == "internal" and .kind == "runtime-routed-prefix-return" and (.via != null))
    and ([p2p_gua_addresses] | length) == 0
' "${output_json}" >/dev/null || {
  echo "FAIL runtime-gua-return-routes: NFM must route runtime GUA prefixes over ULA p2p hops" >&2
  jq '
    .enterprise.acme.site.ams as $site
    | {
        sourceRoutes: [
          $site.nodes
          | to_entries[]
          | . as $node
          | ($node.value.interfaces // {})
          | to_entries[]
          | (.value.routes.ipv6 // [])[]
          | select((.sourceFile // null) == "/run/s88-ipv6-pd/wan.prefix")
          | { node: $node.key, interface: .key, route: . }
        ],
        p2pAddresses: [
          $site.nodes
          | to_entries[]
          | . as $node
          | ($node.value.interfaces // {})
          | to_entries[]
          | select((.value.kind // "") == "p2p")
          | { node: $node.key, interface: .key, addr6: (.value.addr6 // .value.ipv6 // null) }
        ]
      }
  ' "${output_json}" >&2
  exit 1
}

pass_timed "runtime-gua-return-routes"
