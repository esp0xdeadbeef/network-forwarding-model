#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-370-HDS-010-SDS-010-SMS-070
# GAMP-SCOPE: software-module-test
#
# Focused construction test: core forwarding chain.
# SMS-070 requires the core node to carry tenant transit routes through
# the fabric chain toward WAN with correct intent classes.
#
# Seeded negatives:
#   - Tenant subnet missing from core routes
#   - Missing fabric stage

repo_root="$(git rev-parse --show-toplevel)"
source "${repo_root}/tests/lib/timing.sh"
tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

input_nix="${tmpdir}/compiler-output.nix"
output_json="${tmpdir}/out.json"

cat >"${input_nix}" <<'NIX'
{
  sites.acme.ams = {
    addressPools = {
      local.ipv4 = "10.37.0.0/24";
      p2p.ipv4 = "10.37.1.0/24";
      p2p.ipv6 = "fd42:370::/118";
    };

    attachments = [
      { unit = "access-client"; kind = "tenant"; name = "client"; }
    ];

    domains = {
      externals = [ { kind = "external"; name = "wan"; } ];
      tenants = [
        { kind = "tenant"; name = "client"; ipv4 = "10.37.20.0/24"; ipv6 = "fd42:370:20::/64"; }
      ];
    };

    communicationContract.relations = [
      { id = "allow-client-to-wan"; priority = 100;
        from = { kind = "tenant"; name = "client"; };
        to = { kind = "external"; uplinks = [ "wan" ]; };
        trafficType = "any"; action = "allow"; }
    ];

    transit.ordering = [
      [ "access-client" "downstream" ]
      [ "downstream" "policy" ]
      [ "policy" "upstream" ]
      [ "upstream" "core-wan" ]
    ];

    units = {
      access-client.role = "access";
      downstream.role = "downstream-selector";
      policy.role = "policy";
      upstream.role = "upstream-selector";
      core-wan = { role = "core"; uplinks.wan.ipv4 = [ "0.0.0.0/0" ]; uplinks.wan.ipv6 = [ "::/0" ]; };
    };
  };
}
NIX

start_ms="$(test_now_ms)"
nix run "${repo_root}#compile-and-build-forwarding-model" -- "${input_nix}" >"${output_json}"
pass_timed "fs370-sms070-core-forwarding-chain:compile" "${start_ms}"

# Predicate 1: Core node exists with routes
jq -e '
  .enterprise.acme.site.ams.nodes["core-wan"]
  | (.interfaces // {}) | length > 0
' "${output_json}" >/dev/null || {
  echo "FAIL fs370-sms070: core node must exist with interfaces and routes" >&2
  exit 1
}

# Predicate 2: Core has a route for the tenant subnet (return path)
jq -e '
  .enterprise.acme.site.ams as $site
  | $site.nodes["core-wan"] as $core
  | def tenant_routes:
      ($core.interfaces // {})
      | to_entries[]
      | .value.routes.ipv4[]?
      | select(.dst == "10.37.20.0/24");
  any(tenant_routes; true)
' "${output_json}" >/dev/null || {
  echo "FAIL fs370-sms070: core node must have a route for tenant subnet 10.37.20.0/24" >&2
  jq '[.enterprise.acme.site.ams.nodes["core-wan"].interfaces | to_entries[] | .value.routes.ipv4[]? | {dst, intent_kind: .intent.kind, via4}]' "${output_json}" >&2
  exit 1
}

# Predicate 3: Core tenant route carries internal-reachability intent
jq -e '
  .enterprise.acme.site.ams as $site
  | $site.nodes["core-wan"] as $core
  | def tenant_return:
      ($core.interfaces // {})
      | to_entries[]
      | .value.routes.ipv4[]?
      | select(.dst == "10.37.20.0/24" and .intent.kind == "internal-reachability");
  any(tenant_return; true)
' "${output_json}" >/dev/null || {
  echo "FAIL fs370-sms070: core tenant subnet route must carry internal-reachability intent" >&2
  exit 1
}

# Seeded negative 1: Verify all 5 fabric chain stages present
jq -e '
  .enterprise.acme.site.ams.nodes
  | has("access-client") and has("downstream") and has("policy") and has("upstream") and has("core-wan")
' "${output_json}" >/dev/null || {
  echo "FAIL fs370-sms070: all 5 fabric stages (access→selector→policy→selector→core) must be present" >&2
  exit 1
}

# Seeded negative 2: Verify upstreamSelectorNodeName and coreNodeNames are set
jq -e '
  .enterprise.acme.site.ams
  | .upstreamSelectorNodeName == "upstream"
  and (.coreNodeNames | index("core-wan") != null)
' "${output_json}" >/dev/null || {
  echo "FAIL fs370-sms070: site must identify upstreamSelectorNodeName and coreNodeNames for forwarding chain" >&2
  exit 1
}

pass_timed "fs370-sms070-core-forwarding-chain"
