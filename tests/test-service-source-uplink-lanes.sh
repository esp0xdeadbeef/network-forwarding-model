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
  esp0xdeadbeef."site-a" = {
    pools.p2p.ipv4 = "10.10.0.0/24";
    pools.loopback.ipv4 = "10.19.0.0/24";

    ownership.prefixes = [
      { kind = "tenant"; name = "client"; ipv4 = "10.20.20.0/24"; }
      { kind = "tenant"; name = "dmz"; ipv4 = "10.20.30.0/24"; }
    ];
    ownership.endpoints = [
      { kind = "host"; name = "dns-dmz"; tenant = "dmz"; }
    ];

    communicationContract = {
      trafficTypes = [
        { name = "dns"; match = [ { family = "any"; proto = "udp"; dports = [ 53 ]; } { family = "any"; proto = "tcp"; dports = [ 53 ]; } ]; }
      ];
      services = [
        { name = "dns-dmz"; providers = [ "dns-dmz" ]; trafficType = "dns"; }
      ];
      relations = [
        { id = "allow-client-to-uplink0"; priority = 90; from = { kind = "tenant"; name = "client"; }; to = { kind = "external"; uplinks = [ "uplink0" ]; }; trafficType = "any"; action = "allow"; }
        { id = "allow-dmz-dns-to-uplink0"; priority = 100; from = { kind = "service"; name = "dns-dmz"; }; to = { kind = "external"; uplinks = [ "uplink0" ]; }; trafficType = "dns"; action = "allow"; }
      ];
    };

    topology.nodes = {
      s-router-access-client = { role = "access"; attachments = [ { kind = "tenant"; name = "client"; } ]; };
      s-router-access-dmz = { role = "access"; attachments = [ { kind = "tenant"; name = "dmz"; } ]; };
      s-router-downstream-selector.role = "downstream-selector";
      s-router-policy.role = "policy";
      s-router-upstream-selector.role = "upstream-selector";
      s-router-core = { role = "core"; uplinks.uplink0.ipv4 = [ "0.0.0.0/0" ]; };
    };
    topology.links = [
      [ "s-router-access-client" "s-router-downstream-selector" ]
      [ "s-router-access-dmz" "s-router-downstream-selector" ]
      [ "s-router-downstream-selector" "s-router-policy" ]
      [ "s-router-policy" "s-router-upstream-selector" ]
      [ "s-router-upstream-selector" "s-router-core" ]
    ];
  };
}
EOF

nix run "${repo_root}#compile-and-build-forwarding-model" -- "$input_nix" >"$output_json"

jq -e '
  [
    .enterprise.esp0xdeadbeef.site."site-a".links[]
    | select((.laneMeta.kind // "") == "access-uplink")
    | select(.laneMeta.access == "s-router-access-dmz")
    | select(.laneMeta.uplink == "uplink0")
  ] | length == 1
' "$output_json" >/dev/null

jq -e '
  .enterprise.esp0xdeadbeef.site."site-a".nodes."s-router-policy".interfaces
  | to_entries[]
  | select(.key == "p2p-s-router-policy-s-router-upstream-selector--access-s-router-access-dmz--uplink-uplink0")
  | [.value.routes.ipv4[]?
      | select(.dst == "0.0.0.0/0")
      | select(.reason == "policy-derived-default")
      | select(.policyOnly == true)
      | select(.lane.access == "s-router-access-dmz")
      | select(.lane.uplink == "uplink0")]
  | length == 1
' "$output_json" >/dev/null

pass_timed "service-source-uplink-lanes"
