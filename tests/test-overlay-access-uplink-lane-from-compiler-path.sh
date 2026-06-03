#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-460-HDS-010-SDS-010-SMS-010
# GAMP-SCOPE: software-module-test

repo_root="$(git rev-parse --show-toplevel)"
source "${repo_root}/tests/lib/timing.sh"
tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

input_nix="${tmpdir}/input.nix"
input_json="${tmpdir}/input.json"
model_json="${tmpdir}/model.json"

cat >"${input_nix}" <<'NIX'
{
  sites.acme.ams = {
    addressPools = {
      local.ipv4 = "10.0.0.0/24";
      p2p.ipv4 = "10.0.1.0/24";
    };

    attachments = [
      {
        unit = "access1";
        kind = "tenant";
        name = "tenant-a";
      }
      {
        unit = "core-overlay";
        kind = "tenant";
        name = "tenant-a";
      }
    ];

    communicationContract = {
      allowedRelations = [
        {
          id = "allow-tenant-a-to-east-west";
          action = "allow";
          from = {
            kind = "tenant";
            name = "tenant-a";
          };
          to = {
            kind = "external";
            name = "east-west";
          };
          trafficType = "nebula";
        }
      ];
      services = [ ];
      trafficTypes = [
        {
          name = "nebula";
          match = [
            {
              proto = "udp";
              family = "any";
              dports = [ 4242 ];
            }
          ];
        }
      ];
    };

    domains = {
      externals = [
        {
          kind = "external";
          name = "east-west";
        }
      ];
      tenants = [
        {
          kind = "tenant";
          name = "tenant-a";
          ipv4 = "10.10.0.0/24";
        }
      ];
    };

    trafficPaths = [
      {
        relationId = "allow-tenant-a-to-east-west";
        action = "allow";
        source = {
          kind = "tenant";
          name = "tenant-a";
        };
        destination = {
          kind = "external";
          name = "east-west";
        };
        nodePath = [
          "access1"
          "downstream1"
          "policy1"
          "upstream1"
          "core-overlay"
        ];
      }
    ];

    transit.ordering = [
      [
        "access1"
        "downstream1"
      ]
      [
        "downstream1"
        "policy1"
      ]
      [
        "policy1"
        "upstream1"
      ]
      [
        "upstream1"
        "core-overlay"
      ]
    ];

    transport.overlays = [
      {
        name = "east-west";
        terminateOn = "core-overlay";
        underlayAccess = {
          kind = "tenant";
          name = "tenant-a";
        };
        underlayTrafficTypes = [ "nebula" ];
        mustTraverse = [ "policy" ];
      }
    ];

    upstreams.cores.core-overlay = [
      {
        name = "east-west";
        ipv4 = [ "0.0.0.0/0" ];
      }
    ];

    units = {
      access1.role = "access";
      downstream1.role = "downstream-selector";
      policy1.role = "policy";
      upstream1.role = "upstream-selector";
      core-overlay = {
        role = "core";
        uplinks.east-west.ipv4 = [ "0.0.0.0/0" ];
      };
    };
  };
}
NIX

nix eval --impure --json --expr "import ${input_nix}" >"${input_json}"
nix run "${repo_root}#debug" -- "${input_json}" >"${model_json}"

jq -e '
  .enterprise.acme.site.ams.links["p2p-policy1-upstream1--access-access1--uplink-east-west"] as $lane
  | $lane.lane == "access::access1::uplink::east-west"
    and $lane.laneMeta.kind == "access-uplink"
    and $lane.laneMeta.access == "access1"
    and $lane.laneMeta.uplink == "east-west"
    and $lane.overlay == "east-west"
' "${model_json}" >/dev/null

pass_timed "overlay-access-uplink-lane-from-compiler-path"
