#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-230-HDS-010-SDS-010-SMS-040
# GAMP-SCOPE: software-module-test

repo_root="$(git rev-parse --show-toplevel)"
source "${repo_root}/tests/lib/timing.sh"
tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

input_nix="${tmpdir}/input.nix"
model_json="${tmpdir}/model.json"

cat >"${input_nix}" <<'NIX'
let
  mkSite = relations: {
    addressPools = {
      local = {
        ipv4 = "10.23.0.0/24";
        ipv6 = "fd42:230:ff::/118";
      };
      p2p = {
        ipv4 = "10.23.255.0/24";
        ipv6 = "fd42:230:fe::/118";
      };
    };
    attachments = [
      { unit = "access"; kind = "tenant"; name = "dmz"; }
    ];
    ownership = {
      prefixes = [
        { kind = "tenant"; name = "dmz"; ipv4 = "10.2.30.0/24"; ipv6 = "fd42:230:40::/64"; }
      ];
      endpoints = [
        { kind = "host"; name = "nebula-endpoint"; tenant = "dmz"; }
      ];
    };
    communicationContract = {
      inherit relations;
      services = [
        { name = "nebula"; providers = [ "nebula-endpoint" ]; trafficType = "nebula"; }
      ];
      trafficTypes = [
        { name = "nebula"; match = [ { family = "ipv6"; proto = "udp"; dports = [ 4242 ]; } ]; }
      ];
    };
    transit.ordering = [
      [ "access" "downstream" ]
      [ "downstream" "policy" ]
      [ "policy" "upstream" ]
      [ "upstream" "core" ]
    ];
    units = {
      access.role = "access";
      downstream.role = "downstream-selector";
      policy.role = "policy";
      upstream.role = "upstream-selector";
      core = {
        role = "core";
        uplinks.wan = {
          ipv4 = [ "0.0.0.0/0" ];
          ipv6 = [ "::/0" ];
        };
      };
    };
  };
  ingress = {
    id = "wan-to-nebula";
    action = "allow";
    from = { kind = "external"; uplinks = [ "wan" ]; };
    to = { kind = "service"; name = "nebula"; };
    trafficType = "nebula";
    returnBehavior = "stateful-return";
    publicIngressTupleAuthority = {
      family = "ipv6";
      targetService = "nebula";
      targetPort = 4242;
      tuples = [ { protocol = "udp"; publicPort = 4242; } ];
      translationMode = "none";
      sourcePreservation = "preserve-source";
      returnBehavior = "stateful-return";
    };
  };
  egress = {
    id = "dmz-to-wan";
    action = "allow";
    from = { kind = "tenant"; name = "dmz"; };
    to = { kind = "external"; uplinks = [ "wan" ]; };
    trafficType = "any";
    returnBehavior = "stateful-return";
  };
in
{
  sites.acme = {
    ingress-only = mkSite [ ingress ];
    ingress-and-egress = mkSite [ ingress egress ];
  };
}
NIX

start_ms="$(test_now_ms)"
nix run "${repo_root}#compile-and-build-forwarding-model" -- "${input_nix}" >"${model_json}"
pass_timed "FS-230-ingress-only-egress-authority:compile" "${start_ms}"

jq -e '
  .enterprise.acme.site["ingress-only"] as $in
  | .enterprise.acme.site["ingress-and-egress"] as $out
  | ($in.egressIntent.exitNodeNames == [])
    and ($in.egressIntent.eligibleNodeNames == [])
    and ($in.nodes.core.egressIntent.exit == false)
    and ($in.nodes.core.egressIntent.eligible == false)
    and ($in.nodes.core.egressIntent.nat44 == {})
    and ($in.nodes.upstream.egressIntent.eligible == false)
    and ($out.egressIntent.exitNodeNames == ["core"])
    and ($out.nodes.core.egressIntent.exit == true)
    and ($out.nodes.upstream.egressIntent.eligible == true)
' "${model_json}" >/dev/null

printf 'PASS FS-230-HDS-010-SDS-010-SMS-040 ingress-only authority does not create public egress\n'
