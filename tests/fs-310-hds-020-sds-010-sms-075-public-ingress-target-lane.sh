#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-310-HDS-020-SDS-010-SMS-075
# GAMP-SCOPE: software-module-test

repo_root="$(git rev-parse --show-toplevel)"
source "${repo_root}/tests/lib/timing.sh"
tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

input_nix="${tmpdir}/input.nix"
model_json="${tmpdir}/model.json"

cat >"${input_nix}" <<'NIX'
{
  sites.acme.ams = {
    addressPools = {
      local.ipv4 = "10.31.0.0/24";
      p2p.ipv4 = "10.31.1.0/24";
    };

    attachments = [
      { unit = "access-client"; kind = "tenant"; name = "client"; }
      { unit = "access-dmz"; kind = "tenant"; name = "dmz"; }
      { unit = "access-unrelated"; kind = "tenant"; name = "unrelated"; }
    ];

    ownership = {
      prefixes = [
        { kind = "tenant"; name = "client"; ipv4 = "10.31.10.0/24"; }
        { kind = "tenant"; name = "dmz"; ipv4 = "10.31.20.0/24"; }
        { kind = "tenant"; name = "unrelated"; ipv4 = "10.31.30.0/24"; }
      ];
      endpoints = [
        { kind = "host"; name = "nebula-dmz"; tenant = "dmz"; }
        { kind = "host"; name = "unrelated-host"; tenant = "unrelated"; }
      ];
    };

    communicationContract = {
      services = [
        { name = "nebula"; providers = [ "nebula-dmz" ]; trafficType = "nebula"; }
        { name = "unrelated-service"; providers = [ "unrelated-host" ]; trafficType = "nebula"; }
      ];
      trafficTypes = [
        {
          name = "nebula";
          match = [
            { proto = "udp"; family = "any"; dports = [ 4242 ]; }
          ];
        }
      ];
      relations = [
        {
          id = "client-to-wan";
          action = "allow";
          from = { kind = "tenant"; name = "client"; };
          to = { kind = "external"; uplinks = [ "wan" ]; };
          trafficType = "nebula";
        }
        {
          id = "wan-to-nebula";
          action = "allow";
          from = { kind = "external"; uplinks = [ "wan" ]; };
          to = { kind = "service"; name = "nebula"; };
          trafficType = "nebula";
          publicIngressTupleAuthority = {
            sourceScope = "internet";
            publicSurface = "wan";
            targetService = "nebula";
            targetEndpoint = "nebula-dmz";
            targetPort = 4242;
            returnBehavior = "stateful-return";
            translationMode = "napt";
            sourcePreservation = "rewritten";
            hairpin = "not-modeled";
            asymmetricRouting = "not-allowed";
            tuples = [ { protocol = "udp"; publicPort = 4242; } ];
          };
        }
        {
          id = "wan-to-unrelated-without-public-ingress-authority";
          action = "allow";
          from = { kind = "external"; uplinks = [ "wan" ]; };
          to = { kind = "service"; name = "unrelated-service"; };
          trafficType = "nebula";
        }
      ];
    };

    transit.ordering = [
      [ "access-client" "downstream" ]
      [ "access-dmz" "downstream" ]
      [ "access-unrelated" "downstream" ]
      [ "downstream" "policy" ]
      [ "policy" "upstream" ]
      [ "upstream" "core" ]
    ];

    units = {
      access-client.role = "access";
      access-dmz.role = "access";
      access-unrelated.role = "access";
      downstream.role = "downstream-selector";
      policy.role = "policy";
      upstream.role = "upstream-selector";
      core = {
        role = "core";
        uplinks.wan.ipv4 = [ "0.0.0.0/0" ];
      };
    };
  };
}
NIX

start_ms="$(test_now_ms)"
nix run "${repo_root}#compile-and-build-forwarding-model" -- "${input_nix}" >"${model_json}"
pass_timed "fs-310-public-ingress-target-lane:compile" "${start_ms}"

jq -e '
  .enterprise.acme.site.ams.links as $links
  | $links["p2p-policy-upstream--access-access-dmz--uplink-wan"] as $ingress
  | ($ingress.lane == "access::access-dmz::uplink::wan")
    and ($ingress.laneMeta.kind == "access-uplink")
    and ($ingress.laneMeta.access == "access-dmz")
    and ($ingress.laneMeta.uplink == "wan")
    and ($links["p2p-policy-upstream--access-access-client--uplink-wan"] != null)
    and ($links["p2p-policy-upstream--access-access-unrelated--uplink-wan"] == null)
' "${model_json}" >/dev/null

pass_timed "fs-310-public-ingress-target-lane:authority-bounded"
