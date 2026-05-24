#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
source "${repo_root}/tests/lib/timing.sh"
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
      local.ipv6 = "fd42:0:0:1900::/64";
      p2p.ipv4 = "10.0.1.0/24";
      p2p.ipv6 = "fd42:0:0:1000::/64";
    };

    domains = {
      tenants = [
        {
          kind = "tenant";
          name = "client";
          ipv4 = "10.10.0.0/24";
          ipv6 = "fd42:10::/64";
        }
      ];
      externals = [ { kind = "external"; name = "wan"; } ];
    };

    communicationContract.relations = [
      {
        id = "allow-client-wan";
        priority = 100;
        from = { kind = "tenant"; name = "client"; };
        to = { kind = "external"; name = "wan"; };
        trafficType = "any";
        action = "allow";
      }
    ];

    overlayAttachments."east-west" = {
      accessNodes = [ "access-client" ];
      terminatesOn = [ "core-overlay" ];
      canonicalPath = [ "core-wan" "upstream" "policy" "downstream" "access-client" "overlay:east-west" ];
      attachAfterStage = "access";
      site = "acme.ams";
    };

    topology.nodes = {
      access-client = {
        role = "access";
        attachments = [ { kind = "tenant"; name = "client"; } ];
      };
      downstream.role = "downstream-selector";
      policy.role = "policy";
      upstream.role = "upstream-selector";
      core-wan = {
        role = "core";
        uplinks.wan.ipv4 = [ "0.0.0.0/0" ];
        uplinks.wan.ipv6 = [ "::/0" ];
      };
      core-overlay = {
        role = "core";
        attachments = [ { kind = "tenant"; name = "client"; } ];
        uplinks."east-west".ipv4 = [ "0.0.0.0/0" ];
        uplinks."east-west".ipv6 = [ "::/0" ];
      };
    };

    topology.links = [
      [ "access-client" "downstream" ]
      [ "downstream" "policy" ]
      [ "policy" "upstream" ]
      [ "upstream" "core-wan" ]
    ];
  };
}
EOF

nix eval --json --impure --expr "import ${input_nix}" >"${ir_json}"
nix run "${repo_root}#debug" -- "${ir_json}" >"${model_json}"

if jq -e '
  .enterprise.acme.site.ams as $site
  | ($site.nodes."access-client".interfaces."p2p-access-client-downstream".routes // {}) as $accessTransitRoutes
  | (($site.links // {}) | to_entries | map(select((.value.members // [] | index("core-overlay")) and (.value.members // [] | index("access-client"))))) as $coreAccessLinks
  | (($site.nodes."core-overlay".loopback.ipv4 | sub("/.*$"; "") + "/32")) as $coreLoopback4
  | (($site.nodes."core-overlay".loopback.ipv6 | sub("/.*$"; "") + "/128")) as $coreLoopback6
  | ($site.nodes.upstream.interfaces."p2p-policy-upstream--access-access-client--uplink-wan".routes // {}) as $upstreamPolicyRoutes
  | ($coreAccessLinks == [])
  and (
      (($accessTransitRoutes.ipv4 // []) | any(.intent.kind == "default-reachability" and .dst == "0.0.0.0/0"))
      and (($accessTransitRoutes.ipv6 // []) | any(.intent.kind == "default-reachability" and .dst == "::/0"))
    )
  and (
      (($upstreamPolicyRoutes.ipv4 // []) | any(.intent.kind == "internal-reachability" and .dst == $coreLoopback4))
      and (($upstreamPolicyRoutes.ipv6 // []) | any(.intent.kind == "internal-reachability" and .dst == $coreLoopback6))
    )
' "${model_json}" >/dev/null; then
  pass_timed "overlay-underlay-access-default-routes"
else
  cat >&2 <<'EOF'
FATAL network-forwarding-model overlay underlay access defaults regressed.

Overlay daemon underlay may enter through an explicitly selected access node,
but the selected access node must not default-route back into the overlay core.
The overlay-terminating core is a host-like tenant attachment, not a generated
core/access p2p link, and the selected access node must keep its normal default
toward downstream transit so runtime overlay bootstrap can use the normal
access/downstream/policy/upstream path instead of either a self-loop or a
dead-end access hop.
EOF
  exit 1
fi
