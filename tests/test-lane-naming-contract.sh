#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: SMT-NFM-LANE-NAMING-001
# GAMP-SCOPE: software-module-test

repo_root="$(git rev-parse --show-toplevel)"
source "${repo_root}/tests/lib/timing.sh"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

input_file="$tmpdir/input.nix"
actual="$tmpdir/actual.txt"
expected="$tmpdir/expected.txt"
system="${NIX_SYSTEM:-$(nix eval --impure --raw --expr 'builtins.currentSystem')}"

cat >"$input_file" <<'EOF'
{
  sites.acme.ams = {
    addressPools = {
      local.ipv4 = "10.0.0.0/24";
      p2p.ipv4 = "10.0.1.0/24";
    };

    attachments = [
      { unit = "access1"; kind = "tenant"; name = "tenant-a"; }
    ];

    domains = {
      externals = [
        { kind = "external"; name = "wan0"; }
        { kind = "external"; name = "wan1"; }
      ];
      tenants = [
        { kind = "tenant"; name = "tenant-a"; ipv4 = "10.10.0.0/24"; }
      ];
    };

    communicationContract.allowedRelations = [
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

    transit.ordering = [
      [ "access1" "downstream1" ]
      [ "downstream1" "policy1" ]
      [ "policy1" "upstream1" ]
      [ "upstream1" "coreA" ]
      [ "upstream1" "coreB" ]
    ];

    upstreams.cores = {
      coreA = [
        {
          name = "wan0";
          addr4 = "198.51.100.2/31";
          peerAddr4 = "198.51.100.3";
          ipv4 = [ "0.0.0.0/0" ];
        }
      ];
      coreB = [
        {
          name = "wan1";
          addr4 = "203.0.113.2/31";
          peerAddr4 = "203.0.113.3";
          ipv4 = [ "0.0.0.0/0" ];
        }
      ];
    };

    units = {
      access1.role = "access";
      downstream1.role = "downstream-selector";
      policy1.role = "policy";
      upstream1.role = "upstream-selector";
      coreA.role = "core";
      coreB.role = "core";
    };
  };
}
EOF

cat >"$expected" <<'EOF'
p2p-access1-downstream1
p2p-coreA-upstream1
p2p-coreB-upstream1
p2p-downstream1-policy1--access-access1
p2p-policy1-upstream1--access-access1--uplink-wan0
p2p-policy1-upstream1--access-access1--uplink-wan1
wan-coreA-wan0
wan-coreB-wan1
EOF

expr="$(cat <<EOF
let
  flake = builtins.getFlake "${repo_root}";
  input = import "${input_file}";
  out = flake.libBySystem."${system}".build { inherit input; };
in
  builtins.toJSON (builtins.attrNames out.enterprise.acme.site.ams.links)
EOF
)"

nix eval --impure --raw --expr "$expr" | jq -r '.[]' >"$actual"

if diff -u "$expected" "$actual"; then
  pass_timed "lane-naming-contract"
else
  echo "FAIL lane-naming-contract: emitted lane/link identities changed" >&2
  exit 1
fi
