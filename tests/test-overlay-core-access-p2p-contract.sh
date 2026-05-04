#!/usr/bin/env bash
set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

input_nix="${tmpdir}/input.nix"
ir_json="${tmpdir}/ir.json"
model_json="${tmpdir}/model.json"

cat >"${input_nix}" <<'EOF'
{
  sites.acme.ams = {
    addressPools = {
      local.ipv4 = "10.0.0.0/24";
      p2p.ipv4 = "10.0.1.0/24";
      p2p.ipv6 = "fd42:0:0:1000::/64";
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
          name = "east-west";
        }
      ];

      tenants = [
        {
          kind = "tenant";
          name = "tenant-a";
          ipv4 = "10.10.0.0/24";
          ipv6 = "fd42:10:a::/64";
        }
      ];
    };

    communicationContract.relations = [
      {
        id = "allow-tenant-a-to-east-west";
        priority = 100;
        from = { kind = "tenant"; name = "tenant-a"; };
        to = { kind = "external"; name = "east-west"; };
        trafficType = "any";
        action = "allow";
      }
    ];

    transit.ordering = [
      [ "access1" "downstream1" ]
      [ "downstream1" "policy1" ]
      [ "policy1" "upstream1" ]
      [ "upstream1" "core-wan" ]
      [ "upstream1" "core-overlay" ]
    ];

    transport.overlays = [
      {
        name = "east-west";
        terminateOn = "core-overlay";
        prefixes = {
          ipv4 = [ "100.96.20.0/24" ];
          ipv6 = [ "fd42:dead:beef:20::/64" ];
        };
      }
    ];

    units = {
      access1.role = "access";
      downstream1.role = "downstream-selector";
      policy1.role = "policy";
      upstream1.role = "upstream-selector";
      core-wan = {
        role = "core";
        uplinks.wan.ipv4 = [ "0.0.0.0/0" ];
      };
      core-overlay = {
        role = "core";
        uplinks.east-west.ipv4 = [ "100.96.20.0/24" ];
        uplinks.east-west.ipv6 = [ "fd42:dead:beef:20::/64" ];
      };
    };
  };
}
EOF

nix eval --json --impure --expr "import ${input_nix}" >"${ir_json}"
nix run "${repo_root}#debug" -- "${ir_json}" >"${model_json}"

if jq -e '
  .enterprise.acme.site.ams as $site
  | ($site.links | to_entries | any(
      .value.kind == "p2p"
      and (.value.lane // "" | contains("access::access1"))
      and (.value.overlay // null) == "east-west"
      and ((.value.members // []) | index("policy1") != null)
      and ((.value.members // []) | index("upstream1") != null)
    ))
  and ($site.nodes.policy1.interfaces | to_entries | any(
      .key == "p2p-policy1-upstream1--access-access1--uplink-east-west"
      and ((.value.routes.ipv4 // []) | any(.dst == "100.96.20.0/24"))
    ))
  and ($site.nodes.upstream1.interfaces | to_entries | any(
      .key == "p2p-core-overlay-upstream1"
      and ((.value.routes.ipv4 // []) | any(.dst == "100.96.20.0/24"))
    ))
  and ($site.links | to_entries | all(
      ((.value.members // []) | index("access1") != null)
      and (((.value.members // []) | index("core-overlay") != null) or (((.value.members // []) | index("overlay:east-west") != null)))
      | not
    ))
' "${model_json}" >/dev/null; then
  echo "PASS overlay-core-access-p2p-contract"
else
  cat >&2 <<'EOF'
FATAL network-forwarding-model overlay core/access p2p contract is not implemented yet.

This red failure may be removed only after network-forwarding-model derives the
forwarding consequences of compiler overlay semantics:

  - deterministic p2p/lane structure for access -> overlay reachability
  - routes for the full overlay prefixes only on zones/lane paths allowed by policy
  - no overlay routes on denied zones
  - no Nebula/WireGuard/OpenVPN-specific fake clients or renderer-side p2p invention

The compiler owns semantic overlay placement. FWM owns the executable p2p/lane
and route shape. Renderers must never invent these links from names.
EOF
  exit 1
fi
