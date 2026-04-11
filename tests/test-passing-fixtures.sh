#!/usr/bin/env bash
set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

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

write_positive_input() {
  cat > "$1" <<'EOF'
{
  sites = {
    acme = {
      ams = {
        addressPools = {
          local = {
            ipv4 = "10.0.0.0/24";
          };

          p2p = {
            ipv4 = "10.0.1.0/24";
          };
        };

        attachments = [
          {
            unit = "access1";
            kind = "tenant";
            name = "tenant-a";
          }
        ];

        domains = {
          externals = [
            {
              kind = "external";
              name = "internet";
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

        transit = {
          ordering = [
            [
              "access1"
              "policy1"
            ]
            [
              "policy1"
              "core1"
            ]
          ];
        };

        units = {
          access1 = {
            role = "access";
          };

          policy1 = {
            role = "policy";
          };

          core1 = {
            role = "core";
            uplinks = {
              internet = {
                addr4 = "198.51.100.2/31";
                peerAddr4 = "198.51.100.3";
                ipv4 = [ "203.0.113.0/24" ];
              };
            };
          };
        };
      };
    };
  };
}
EOF
}

positive_input="$tmpdir/positive.nix"
write_positive_input "$positive_input"

expr_minimal="$(cat <<EOF
let
  flake = builtins.getFlake "${repo_root}";
  input = import "${positive_input}";
  out = flake.lib.x86_64-linux.build { inherit input; };
  site = out.enterprise.acme.site.ams;
  iface = site.nodes.access1.interfaces."tenant-tenant-a";
  expectedOrdering = [
    "link::acme.ams::p2p-access1-policy1"
    "link::acme.ams::p2p-core1-policy1"
  ];
  expectedLinks = [
    "p2p-access1-policy1"
    "p2p-core1-policy1"
    "wan-core1-internet"
  ];
in
  if
    site.siteName == "acme.ams"
    && site.topology.links == [
      [
        "access1"
        "policy1"
      ]
      [
        "policy1"
        "core1"
      ]
    ]
    && site.transit.ordering == expectedOrdering
    && (map (adj: toString adj.id) (site.transit.adjacencies or [ ])) == expectedOrdering
    && (site.policyNodeName or null) == "policy1"
    && (site.coreNodeNames or [ ]) == [ "core1" ]
    && (site.upstreamSelectorNodeName or null) == null
    && (builtins.attrNames (site.nodes or { })) == [ "access1" "core1" "policy1" ]
    && (builtins.attrNames (site.links or { })) == expectedLinks
    && builtins.hasAttr "tenant-tenant-a" (site.nodes.access1.interfaces or { })
    && (iface.network.name or null) == "tenant-a"
    && builtins.elem "access-gateway" (site.nodes.access1.forwardingFunctions or [ ])
    && ((site.nodes.core1.egressIntent.exit or false) == true)
  then
    "ok"
  else
    throw "positive-minimal assertion failed"
EOF
)"

if ! nix eval --impure --raw --expr "$expr_minimal" >/dev/null; then
  fail "positive-minimal"
fi
pass "positive-minimal"

expr_deterministic="$(cat <<EOF
let
  flake = builtins.getFlake "${repo_root}";
  input = import "${positive_input}";
  out1 = flake.lib.x86_64-linux.build { inherit input; };
  out2 = flake.lib.x86_64-linux.build { inherit input; };
in
  if builtins.toJSON out1 == builtins.toJSON out2 then
    "ok"
  else
    throw "deterministic-output assertion failed"
EOF
)"

if ! nix eval --impure --raw --expr "$expr_deterministic" >/dev/null; then
  fail "deterministic-output"
fi
pass "deterministic-output"
