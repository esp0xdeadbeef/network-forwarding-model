#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-520-HDS-010-SDS-010-SMS-010
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
      local.ipv4 = "10.52.0.0/24";
      p2p.ipv4 = "10.52.1.0/24";
      p2p.ipv6 = "fd42:520::/118";
    };

    attachments = [
      { unit = "access-client"; kind = "tenant"; name = "client"; }
    ];

    domains = {
      externals = [ { kind = "external"; name = "route-import"; } ];
      tenants = [
        { kind = "tenant"; name = "client"; ipv4 = "10.52.20.0/24"; }
      ];
    };

    uplinks.cores.core-route-import = [
      {
        name = "route-import";
        addr4 = "198.51.100.2/30";
        peerAddr4 = "198.51.100.1/30";
        addr6 = "2001:db8:520::2/127";
        peerAddr6 = "2001:db8:520::1/127";
      }
    ];

    communicationContract.relations = [
      {
        id = "allow-client-to-route-import";
        priority = 100;
        from = { kind = "tenant"; name = "client"; };
        to = { kind = "external"; uplinks = [ "route-import" ]; };
        trafficType = "any";
        action = "allow";
        returnBehavior = "symmetric";
      }
    ];

    transit.ordering = [
      [ "access-client" "downstream" ]
      [ "downstream" "policy" ]
      [ "policy" "upstream" ]
      [ "upstream" "core-route-import" ]
    ];

    units = {
      access-client.role = "access";
      downstream.role = "downstream-selector";
      policy.role = "policy";
      upstream.role = "upstream-selector";
      core-route-import = {
        role = "core";
        uplinks.route-import = {
          ipv4 = [ "198.51.100.0/24" ];
          ipv6 = [ "2001:db8:51::/48" ];
        };
      };
    };
  };
}
NIX

start_ms="$(test_now_ms)"
nix run "${repo_root}#compile-and-build-forwarding-model" -- "${input_nix}" >"${output_json}"
pass_timed "fs520-runtime-route-import-explanation:compile" "${start_ms}"

jq -e '
  .enterprise.acme.site.ams as $site
  | [
      $site.nodes
      | to_entries[]
      | .value.interfaces
      | to_entries[]
      | (.value.routes.ipv4[]?, .value.routes.ipv6[]?)
      | select(.intent.kind == "uplink-learned-reachability")
    ] as $learned
  | ($learned | length >= 4)
    and all($learned[];
      (.intent.source == "explicit-uplink")
      and (.intent.routeSource == "explicit-uplink")
      and (.intent.sourcePeerOrProvider == "route-import")
      and (.intent.routePurpose == "provider-prefix")
      and (.intent.maximumScope == "provider")
      and (.intent.rejectionBehavior == "reject")
      and (.intent.routeAvailabilityOnly == true)
      and (.intent.policyAuthority == false)
    )
    and ([ $learned[] | select(.dst == "198.51.100.0/24") ] | length >= 1)
    and ([ $learned[] | select(.dst == "2001:0db8:0051:0000:0000:0000:0000:0000/48") ] | length >= 1)
' "${output_json}" >/dev/null || {
  echo "FAIL fs520-runtime-route-import-explanation: uplink-learned routes lack route explanation metadata" >&2
  jq '.enterprise.acme.site.ams.nodes | to_entries[] | {node: .key, interfaces: .value.interfaces}' "${output_json}" >&2
  exit 1
}

pass_timed "fs520-runtime-route-import-explanation"
