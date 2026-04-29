#!/usr/bin/env bash
set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

system="${NIX_SYSTEM:-$(nix eval --impure --raw --expr 'builtins.currentSystem')}"

pass() {
  printf 'PASS %s\n' "$1"
}

fail() {
  printf 'FAIL %s\n' "$1" >&2
  if [ "${2-}" != "" ]; then
    printf '%s\n' "$2" >&2
  fi
  exit 1
}

write_input() {
  cat > "$1" <<'EOF'
{
  sites = {
    acme = {
      ams = {
        addressPools = {
          local = {
            ipv4 = "10.0.0.0/24";
            ipv6 = "fd42:0:0:1::/64";
          };
          p2p = {
            ipv4 = "10.0.1.0/24";
            ipv6 = "fd42:0:0:1000::/64";
          };
        };

        communicationContract = {
          allowedRelations = [
            {
              id = "allow-tenant-a-to-uplinks";
              action = "allow";
              from = { kind = "tenant"; name = "tenant-a"; };
              to = { kind = "external"; uplinks = [ "wan0" "wan1" ]; };
              trafficType = "any";
              source = { kind = "relation"; id = "allow-tenant-a-to-uplinks"; priority = 100; };
              match = [ { proto = "any"; family = "any"; dports = [ ]; } ];
            }
          ];
          services = [ ];
          trafficTypes = [ ];
        };

        # Some upstream layers materialize overlay names as external domains.
        # WAN-discovered uplinks must still be the only default-reachability
        # uplink set; overlays get specific reachability, not defaults.
        uplinkNames = [ "east-west" "wan0" "wan1" ];
        transport.overlays = [
          { name = "east-west"; }
        ];

        attachments = [
          { unit = "access1"; kind = "tenant"; name = "tenant-a"; }
        ];

        domains = {
          externals = [
            { kind = "external"; name = "wan0"; }
            { kind = "external"; name = "wan1"; }
          ];
          tenants = [
            {
              kind = "tenant";
              name = "tenant-a";
              ipv4 = "10.10.0.0/24";
              ipv6 = "fd42:0:0:10::/64";
            }
          ];
        };

        transit = {
          ordering = [
            [ "access1" "downstream1" ]
            [ "downstream1" "policy1" ]
            [ "policy1" "upstream1" ]
            [ "upstream1" "coreA" ]
            [ "upstream1" "coreB" ]
          ];
        };

        upstreams = {
          cores = {
            coreA = [
              {
                name = "wan0";
                addr4 = "198.51.100.2/31";
                peerAddr4 = "198.51.100.3";
                addr6 = "2001:db8:1::2/127";
                peerAddr6 = "2001:db8:1::3";
                ipv4 = [ "0.0.0.0/0" ];
                ipv6 = [ "::/0" ];
              }
            ];
            coreB = [
              {
                name = "wan1";
                addr4 = "203.0.113.2/31";
                peerAddr4 = "203.0.113.3";
                addr6 = "2001:db8:2::2/127";
                peerAddr6 = "2001:db8:2::3";
                ipv4 = [ "0.0.0.0/0" ];
                ipv6 = [ "::/0" ];
              }
            ];
          };
        };

        units = {
          access1 = { role = "access"; };
          downstream1 = { role = "downstream-selector"; };
          policy1 = { role = "policy"; };
          upstream1 = { role = "upstream-selector"; };
          coreA = { role = "core"; };
          coreB = { role = "core"; };
        };
      };
    };
  };
}
EOF
}

input_file="$tmpdir/input.nix"
write_input "$input_file"

expr="$(cat <<EOF
let
  flake = builtins.getFlake "${repo_root}";
  input = import "${input_file}";
  out = flake.libBySystem."${system}".build { inherit input; };
  site = out.enterprise.acme.site.ams;
  linkNames = builtins.attrNames (site.links or { });
  downstream = site.nodes.downstream1;
  uplinkNames = site.uplinkNames or [ ];

  isLane = name: builtins.match "p2p-policy1-upstream1--access-access1--uplink-.*" name != null;
  policyUpstreamLaneLinks = builtins.filter isLane linkNames;

  isDsLane = name: builtins.match "p2p-downstream1-policy1--access-access1" name != null;
  dsPolicyLaneLinks = builtins.filter isDsLane linkNames;

  dsPolicyLane = builtins.head dsPolicyLaneLinks;
  dsPolicyLaneRoutes = downstream.interfaces.\${dsPolicyLane}.routes or { };
  hasRoute = routes: dst: via:
    builtins.any (route: (route.dst or null) == dst && (route.via4 or route.via6 or null) == via) routes;
  hasDefault6 = routes:
    builtins.any (route: (route.dst or null) == "0000:0000:0000:0000:0000:0000:0000:0000/0" && (route.via6 or null) != null) routes;
in
  if
    builtins.length policyUpstreamLaneLinks == 2
    && builtins.length uplinkNames == 2
    && builtins.elem "wan0" uplinkNames
    && builtins.elem "wan1" uplinkNames
    && !(builtins.elem "east-west" uplinkNames)
    && !(builtins.elem "p2p-policy1-upstream1" linkNames)
    && builtins.length dsPolicyLaneLinks == 1
    && !(builtins.elem "p2p-downstream1-policy1" linkNames)
    && hasRoute (dsPolicyLaneRoutes.ipv4 or [ ]) "0.0.0.0/0" "10.0.1.7"
    && hasDefault6 (dsPolicyLaneRoutes.ipv6 or [ ])
  then
    "ok"
  else
    throw "dedicated-lanes assertion failed"
EOF
)"

if ! nix eval --impure --raw --expr "$expr" >/dev/null; then
  fail "dedicated-lanes"
fi

pass "dedicated-lanes"
