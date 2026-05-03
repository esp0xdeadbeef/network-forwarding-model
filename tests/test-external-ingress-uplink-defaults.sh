#!/usr/bin/env bash
set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

system="${NIX_SYSTEM:-$(nix eval --impure --raw --expr 'builtins.currentSystem')}"

cat > "$tmpdir/input.nix" <<'EOF'
{
  sites = {
    acme = {
      ams = {
        addressPools = {
          local.ipv4 = "10.0.0.0/24";
          local.ipv6 = "fd42:0:0:1::/64";
          p2p.ipv4 = "10.0.1.0/24";
          p2p.ipv6 = "fd42:0:0:1000::/64";
        };

        communicationContract = {
          allowedRelations = [
            {
              id = "allow-tenant-a-to-east-west";
              action = "allow";
              from = { kind = "tenant"; name = "tenant-a"; };
              to = { kind = "external"; name = "east-west"; };
              trafficType = "any";
              match = [
                { proto = "any"; dports = [ ]; family = "any"; }
              ];
            }
            {
              id = "allow-tenant-a-to-wan";
              action = "allow";
              from = { kind = "tenant"; name = "tenant-a"; };
              to = { kind = "external"; uplinks = [ "wan0" ]; };
              trafficType = "any";
              match = [
                { proto = "any"; dports = [ ]; family = "any"; }
              ];
            }
            {
              id = "allow-overlay-underlay-to-wan";
              action = "allow";
              from = { kind = "external"; name = "east-west"; };
              to = { kind = "external"; uplinks = [ "wan0" ]; };
              trafficType = "overlay-underlay";
              match = [
                { proto = "any"; dports = [ ]; family = "any"; }
              ];
            }
          ];
          services = [ ];
          trafficTypes = [ ];
        };

        attachments = [
          { unit = "access1"; kind = "tenant"; name = "tenant-a"; }
        ];

        domains = {
          externals = [
            { kind = "external"; name = "east-west"; }
            { kind = "external"; name = "wan0"; }
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

        transit.ordering = [
          [ "access1" "downstream1" ]
          [ "downstream1" "policy1" ]
          [ "policy1" "upstream1" ]
          [ "upstream1" "wanCore" ]
          [ "upstream1" "overlayCore" ]
        ];

        upstreams.cores = {
          wanCore = [
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
          overlayCore = [
            {
              name = "east-west";
              addr4 = "203.0.113.2/31";
              peerAddr4 = "203.0.113.3";
              addr6 = "2001:db8:2::2/127";
              peerAddr6 = "2001:db8:2::3";
              ipv4 = [ "0.0.0.0/0" ];
              ipv6 = [ "::/0" ];
            }
          ];
        };

        units = {
          access1.role = "access";
          downstream1.role = "downstream-selector";
          policy1.role = "policy";
          upstream1.role = "upstream-selector";
          wanCore.role = "core";
          overlayCore.role = "core";
        };
      };
    };
  };
}
EOF

expr="$(cat <<EOF
let
  flake = builtins.getFlake "${repo_root}";
  input = import "${tmpdir}/input.nix";
  out = flake.libBySystem."${system}".build { inherit input; };
  site = out.enterprise.acme.site.ams;
  upstream = site.nodes.upstream1;
  overlayIngress = upstream.interfaces."p2p-overlayCore-upstream1".routes or { };
  hasDefault4 = builtins.any (route:
    (route.dst or null) == "0.0.0.0/0"
    && (route.proto or null) == "default"
    && (route.via4 or null) != null
  ) (overlayIngress.ipv4 or [ ]);
  hasDefault6 = builtins.any (route:
    (route.dst or null) == "0000:0000:0000:0000:0000:0000:0000:0000/0"
    && (route.proto or null) == "default"
    && (route.via6 or null) != null
  ) (overlayIngress.ipv6 or [ ]);
in
  if hasDefault4 && hasDefault6 then "ok" else throw "missing external ingress uplink defaults"
EOF
)"

nix eval --impure --raw --expr "$expr" >/dev/null
printf 'PASS external-ingress-uplink-defaults\n'
