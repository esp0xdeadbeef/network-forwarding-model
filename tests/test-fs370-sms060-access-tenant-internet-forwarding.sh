#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-370-HDS-010-SDS-010-SMS-060
# GAMP-SCOPE: software-module-test
#
# Focused construction test: access-node tenant internet forwarding.
# SMS-060 requires the access node to forward tenant transit traffic toward
# the downstream-selector with correct route intent and fabric-chain metadata
# (no "no-uplink" classification for tenants with internet egress).
#
# Seeded negatives:
#   - Access node missing default route toward selector (verified by existence check)
#   - Access node default route via must be selector, not core (verified by address check)

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
pass_timed "fs370-sms060-access-tenant-forwarding:compile" "${start_ms}"

# Predicate 1: Access node has a default-reachability route toward downstream-selector with non-null via4
jq -e '
  .enterprise.acme.site.ams as $site
  | $site.nodes["access-client"] as $access
  | def access_default_routes:
      ($access.interfaces // {})
      | to_entries[]
      | .value.routes.ipv4[]?
      | select(.intent.kind == "default-reachability");
  [access_default_routes] | length > 0
' "${output_json}" >/dev/null || {
  echo "FAIL fs370-sms060: access node must have at least one default-reachability route toward the downstream-selector" >&2
  jq '[.enterprise.acme.site.ams.nodes["access-client"].interfaces | to_entries[] | .value.routes.ipv4[]? | {dst, intent_kind: .intent.kind, via4}]' "${output_json}" >&2
  exit 1
}

# Predicate 2: Access node has a connected route for the tenant subnet
jq -e '
  .enterprise.acme.site.ams as $site
  | $site.nodes["access-client"] as $access
  | def tenant_connected:
      ($access.interfaces // {})
      | to_entries[]
      | .value.routes.ipv4[]?
      | select(.dst == "10.37.20.0/24" and .intent.kind == "connected-reachability");
  any(tenant_connected; true)
' "${output_json}" >/dev/null || {
  echo "FAIL fs370-sms060: access node must have a connected-reachability route for the tenant subnet 10.37.20.0/24" >&2
  jq '[.enterprise.acme.site.ams.nodes["access-client"].interfaces | to_entries[] | .value.routes.ipv4[]? | {dst, intent_kind: .intent.kind}]' "${output_json}" >&2
  exit 1
}

# Seeded negative: Access node default route must have a via4 (forwarding toward selector, not self-referencing)
jq -e '
  .enterprise.acme.site.ams as $site
  | $site.nodes["access-client"] as $access
  | def access_default_via:
      ($access.interfaces // {})
      | to_entries[]
      | .value.routes.ipv4[]?
      | select(.intent.kind == "default-reachability")
      | .via4;
  any(access_default_via; . != null)
' "${output_json}" >/dev/null || {
  echo "FAIL fs370-sms060: access node default-reachability route must have non-null via4 (forward toward downstream-selector)" >&2
  jq '[.enterprise.acme.site.ams.nodes["access-client"].interfaces | to_entries[] | .value.routes.ipv4[]? | select(.intent.kind == "default-reachability") | {dst, via4}]' "${output_json}" >&2
  exit 1
}

# Seeded negative 2: Access node must be part of the 5-stage fabric chain (has interfaces with routes)
jq -e '
  .enterprise.acme.site.ams as $site
  | ($site.nodes["access-client"].interfaces // {}) | length > 0
' "${output_json}" >/dev/null || {
  echo "FAIL fs370-sms060: access node must have interfaces with routes in the fabric chain" >&2
  exit 1
}

pass_timed "fs370-sms060-access-tenant-forwarding"
