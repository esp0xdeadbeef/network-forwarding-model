#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

input_nix="${tmp_dir}/input.nix"
output_json="${tmp_dir}/forwarding.json"

cat >"$input_nix" <<'NIX'
{
  esp0xdeadbeef = {
    "site-a" = {
      pools = {
        p2p.ipv4 = "10.10.0.0/24";
        p2p.ipv6 = "fd42:dead:beef:1000::/118";
        loopback.ipv4 = "10.19.0.0/24";
        loopback.ipv6 = "fd42:dead:beef:1900::/118";
      };

      ownership.prefixes = [
        { kind = "tenant"; name = "mgmt"; ipv4 = "10.20.10.0/24"; ipv6 = "fd42:dead:beef:20::/64"; }
      ];

      communicationContract.relations = [
        {
          id = "allow-mgmt-to-uplinks";
          priority = 100;
          from = { kind = "tenant"; name = "mgmt"; };
          to = { kind = "external"; uplinks = [ "wan-a" "wan-b" ]; };
          trafficType = "any";
          action = "allow";
        }
      ];

      topology.nodes = {
        access = { role = "access"; attachments = [ { kind = "tenant"; name = "mgmt"; } ]; };
        downstream.role = "downstream-selector";
        policy.role = "policy";
        upstream.role = "upstream-selector";
        core-a = { role = "core"; uplinks.wan-a = { ipv4 = [ "0.0.0.0/0" ]; ipv6 = [ "::/0" ]; }; };
        core-b = { role = "core"; uplinks.wan-b = { ipv4 = [ "0.0.0.0/0" ]; ipv6 = [ "::/0" ]; }; };
      };

      topology.links = [
        [ "access" "downstream" ]
        [ "downstream" "policy" ]
        [ "policy" "upstream" ]
        [ "upstream" "core-a" ]
        [ "upstream" "core-b" ]
      ];
    };
  };
}
NIX

nix run "${repo_root}#compile-and-build-forwarding-model" -- "$input_nix" >"$output_json"

jq -e '
  .enterprise.esp0xdeadbeef.site."site-a".trafficPaths
  | map(select(.relationId == "allow-mgmt-to-uplinks"))
  | .[0]
  | .stagePath == ["access", "downstream-selector", "policy", "upstream-selector", "core"]
    and .corePathNodes == ["core-a", "core-b"]
    and .p2pIsolationKey == "allow-mgmt-to-uplinks"
    and .forbidsCoreToCoreP2P == true
    and (.nodePathAlternatives | length) == 2
' "$output_json" >/dev/null

echo "PASS compiler-traffic-path-propagation"
