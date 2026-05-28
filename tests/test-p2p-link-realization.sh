#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: SMT-NFM-P2P-LINK-001
# GAMP-SCOPE: software-module-test

repo_root="$(git rev-parse --show-toplevel)"
source "${repo_root}/tests/lib/timing.sh"
tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

input_nix="${tmpdir}/input.nix"
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
      { unit = "access1"; kind = "tenant"; name = "tenant-a"; }
    ];

    domains = {
      externals = [ { kind = "external"; name = "wan"; } ];
      tenants = [
        { kind = "tenant"; name = "tenant-a"; ipv4 = "10.10.0.0/24"; ipv6 = "fd42:10:a::/64"; }
      ];
    };

    communicationContract.relations = [
      {
        id = "allow-tenant-a-to-wan";
        priority = 100;
        from = { kind = "tenant"; name = "tenant-a"; };
        to = { kind = "external"; uplinks = [ "wan" ]; };
        trafficType = "any";
        action = "allow";
      }
    ];

    transit.ordering = [
      [ "access1" "downstream1" ]
      [ "downstream1" "policy1" ]
      [ "policy1" "upstream1" ]
      [ "upstream1" "core1" ]
    ];

    units = {
      access1.role = "access";
      downstream1.role = "downstream-selector";
      policy1.role = "policy";
      upstream1.role = "upstream-selector";
      core1 = {
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
  | def p2p_links:
      $site.links
      | to_entries
      | map(select(.value.kind == "p2p"));
    def endpoint_ok($link):
      ($link.value.members | length) == 2
      and ($link.value.endpoints | keys | sort) == ($link.value.members | sort)
      and all($link.value.members[]; $site.nodes[.].interfaces[$link.key].kind == "p2p")
      and all($link.value.endpoints[]; (.addr4 | endswith("/31")) and (.addr6 | endswith("/127")));
    def transit_ids:
      ($site.transit.ordering // []) | sort;
    (p2p_links | length) == 4
    and all(p2p_links[]; endpoint_ok(.))
    and (p2p_links | map(.value.id) | sort) == transit_ids
    and (p2p_links | map(.value.id) | length) == (p2p_links | map(.value.id) | unique | length)
' "${output_json}" >/dev/null

pass_timed "p2p-link-realization"
