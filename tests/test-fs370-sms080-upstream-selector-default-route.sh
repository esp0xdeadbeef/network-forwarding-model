#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-370-HDS-010-SDS-010-SMS-080
# GAMP-SCOPE: software-module-test
#
# Focused construction test: upstream-selector default route behavior.
# SMS-080 requires the upstream-selector to have a single deterministic
# default route toward the core node with proto=default, single nexthop.
#
# Seeded negatives:
#   - Multi-nexthop default route (ECMP) would fail the single-nexthop check
#   - Default route with null via4 would fail

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
pass_timed "fs370-sms080-upstream-selector-default-route:compile" "${start_ms}"

# Predicate 1: Upstream-selector has exactly one default-reachability route on core-facing interface
jq -e '
  .enterprise.acme.site.ams as $site
  | $site.nodes["upstream"] as $us
  | def us_core_defaults:
      ($us.interfaces // {})
      | to_entries[]
      | select(.key | test("core"))
      | .value.routes.ipv4[]?
      | select(.intent.kind == "default-reachability");
  [us_core_defaults] | length == 1
' "${output_json}" >/dev/null || {
  echo "FAIL fs370-sms080: upstream-selector must have exactly one default-reachability route on core-facing interface (not ECMP)" >&2
  jq '[.enterprise.acme.site.ams.nodes["upstream"].interfaces | to_entries[] | select(.key | test("core")) | {iface: .key, defaults: [.value.routes.ipv4[]? | select(.intent.kind == "default-reachability") | {dst, proto, via4}]}]' "${output_json}" >&2
  exit 1
}

# Predicate 2: Default route has proto "default" and non-null via4
jq -e '
  .enterprise.acme.site.ams as $site
  | $site.nodes["upstream"] as $us
  | def us_default:
      ($us.interfaces // {})
      | to_entries[]
      | select(.key | test("core"))
      | .value.routes.ipv4[]?
      | select(.intent.kind == "default-reachability");
  us_default | (.proto == "default" and .via4 != null)
' "${output_json}" >/dev/null || {
  echo "FAIL fs370-sms080: upstream-selector default route must have proto=default and non-null via4" >&2
  exit 1
}

# Predicate 3: Only one default-reachability route TOTAL on upstream-selector (no multi-nexthop)
jq -e '
  .enterprise.acme.site.ams as $site
  | $site.nodes["upstream"] as $us
  | def all_us_defaults:
      ($us.interfaces // {})
      | to_entries[]
      | .value.routes.ipv4[]?
      | select(.intent.kind == "default-reachability");
  [all_us_defaults] | length <= 1
' "${output_json}" >/dev/null || {
  echo "FAIL fs370-sms080: upstream-selector must have at most 1 default-reachability route total (no multi-nexthop/ECMP)" >&2
  jq '[.enterprise.acme.site.ams.nodes["upstream"].interfaces | to_entries[] | {iface: .key, defaults: [.value.routes.ipv4[]? | select(.intent.kind == "default-reachability") | {dst, via4}]}]' "${output_json}" >&2
  exit 1
}

# Seeded negative: Verify default route via4 is a single address, not a subnet
jq -e '
  .enterprise.acme.site.ams as $site
  | $site.nodes["upstream"] as $us
  | def us_default_via:
      ($us.interfaces // {})
      | to_entries[]
      | select(.key | test("core"))
      | .value.routes.ipv4[]?
      | select(.intent.kind == "default-reachability")
      | .via4;
  us_default_via | test("^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$")
' "${output_json}" >/dev/null || {
  echo "FAIL fs370-sms080: upstream-selector default route via4 must be a single IP address (not a subnet or multi-nexthop)" >&2
  exit 1
}

pass_timed "fs370-sms080-upstream-selector-default-route"
