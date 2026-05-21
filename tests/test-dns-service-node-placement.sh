#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)"
source "${repo_root}/tests/lib/timing.sh"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

input_nix="${tmp_dir}/input.nix"
output_json="${tmp_dir}/forwarding.json"

cat >"$input_nix" <<'EOF'
{
  acme.ams = {
    pools.p2p.ipv4 = "10.10.0.0/24";
    pools.loopback.ipv4 = "10.19.0.0/24";

    ownership.prefixes = [
      { kind = "tenant"; name = "client"; ipv4 = "10.20.20.0/24"; }
    ];
    ownership.endpoints = [
      { kind = "host"; name = "dns-mgmt"; tenant = "client"; }
    ];

    communicationContract = {
      trafficTypes = [
        { name = "dns"; match = [ { family = "any"; proto = "udp"; dports = [ 53 ]; } ]; }
      ];
      services = [
        { name = "site-dns"; providers = [ "dns-mgmt" ]; trafficType = "dns"; }
      ];
      relations = [
        { id = "allow-client-to-dns"; from = { kind = "tenant"; name = "client"; }; to = { kind = "service"; name = "site-dns"; }; trafficType = "dns"; action = "allow"; }
        { id = "allow-client-to-wan"; from = { kind = "tenant"; name = "client"; }; to = { kind = "external"; uplinks = [ "wan-a" "wan-b" ]; }; trafficType = "any"; action = "allow"; }
      ];
    };

    upstreams.cores = {
      core-a = [
        { name = "wan-a"; ipv4 = [ "0.0.0.0/0" ]; }
      ];
      core-b = [
        { name = "wan-b"; ipv4 = [ "0.0.0.0/0" ]; }
      ];
    };

    topology.nodes = {
      access = { role = "access"; attachments = [ { kind = "tenant"; name = "client"; } ]; };
      downstream.role = "downstream-selector";
      policy.role = "policy";
      upstream.role = "upstream-selector";
      core-a = { role = "core"; uplinks.wan-a.ipv4 = [ "0.0.0.0/0" ]; };
      core-nebula = { role = "core"; uplinks.east-west.ipv4 = [ "100.96.0.0/24" ]; };
      core-b = { role = "core"; uplinks.wan-b.ipv4 = [ "0.0.0.0/0" ]; };
    };
    topology.links = [
      [ "access" "downstream" ]
      [ "downstream" "policy" ]
      [ "policy" "upstream" ]
      [ "upstream" "core-a" ]
      [ "upstream" "core-nebula" ]
      [ "upstream" "core-b" ]
    ];
  };
}
EOF

nix run "${repo_root}#compile-and-build-forwarding-model" -- "$input_nix" >"$output_json"

jq -e '
  .enterprise.acme.site.ams.nodes as $nodes
  | .enterprise.acme.site.ams.forwardingSemantics.dns as $dns
  | ($nodes.access.services.dns == {})
    and ($nodes["core-a"].services.dns == {})
    and ($nodes["core-nebula"].services.dns == {})
    and ($nodes["core-b"].services.dns == {})
    and (($nodes.downstream.services.dns? // null) == null)
    and (($nodes.policy.services.dns? // null) == null)
    and (($nodes.upstream.services.dns? // null) == null)
    and ($dns.serviceNodeNames == ["access", "core-a", "core-b", "core-nebula"])
    and ($dns.accessNodeNames == ["access"])
    and ($dns.nonWanCoreNodeNames == ["core-nebula"])
    and ($dns.wanFallbackNodeNames == ["core-a", "core-b"])
    and ($dns.resolverPreferenceNodeNames == ["access", "core-nebula", "core-a", "core-b"])
' "$output_json" >/dev/null || {
  echo "FAIL dns-service-node-placement" >&2
  jq '{ nodes: (.enterprise.acme.site.ams.nodes | with_entries(.value = { role: .value.role, services: .value.services })), dns: .enterprise.acme.site.ams.forwardingSemantics.dns }' "$output_json" >&2
  exit 1
}

pass_timed "dns-service-node-placement"
