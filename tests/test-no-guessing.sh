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

input_file="$tmpdir/input.nix"
write_input "$input_file"

expr_no_guessing="$(cat <<EOF
let
  flake = builtins.getFlake "${repo_root}";
  input = import "${input_file}";
  out = flake.libBySystem."${system}".build { inherit input; };
  site = out.enterprise.acme.site.ams;
  nodeNames = builtins.attrNames (site.nodes or { });
  linkNames = builtins.attrNames (site.links or { });
in
  if
    nodeNames == [ "access1" "core1" "policy1" ]
    && !builtins.elem "upstream1" nodeNames
    && (site.upstreamSelectorNodeName or null) == null
    && (site.uplinkNames or [ ]) == [ "internet" ]
    && (site.coreNodeNames or [ ]) == [ "core1" ]
    && linkNames == [ "p2p-access1-policy1" "p2p-core1-policy1" "wan-core1-internet" ]
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
    && site.transit.ordering == [
      "link::acme.ams::p2p-access1-policy1"
      "link::acme.ams::p2p-core1-policy1"
    ]
    && builtins.elem "tenant-tenant-a" (builtins.attrNames (site.nodes.access1.interfaces or { }))
    && !builtins.elem "tenant-a" (builtins.attrNames (site.nodes.access1.interfaces or { }))
  then
    "ok"
  else
    throw "no-guessing assertion failed"
EOF
)"

if ! nix eval --impure --raw --expr "$expr_no_guessing" >/dev/null; then
  fail "no-guessing-shape"
fi
pass "no-guessing-shape"

expr_no_inventory_required="$(cat <<EOF
let
  flake = builtins.getFlake "${repo_root}";
  input = import "${input_file}";
  out = flake.libBySystem."${system}".build { inherit input; };
in
  if builtins.isAttrs out.enterprise.acme.site.ams then
    "ok"
  else
    throw "inventory-free build failed"
EOF
)"

if ! nix eval --impure --raw --expr "$expr_no_inventory_required" >/dev/null; then
  fail "inventory-free-build"
fi
pass "inventory-free-build"
