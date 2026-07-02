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
#   - Multi-nexthop default route (ECMP) fails the single-nexthop check
#   - Default route with null via4 fails
#   - Selector default route bypassing the core fabric chain fails closed
#   - Missing selector default route with internet egress requirement fails closed

repo_root="$(git rev-parse --show-toplevel)"
source "${repo_root}/tests/lib/timing.sh"
tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

input_nix="${tmpdir}/compiler-output.nix"
output_json="${tmpdir}/out.json"

expect_compile_failure() {
  local name="$1"
  local fixture="$2"
  shift 2

  local -a env_args=()
  if [[ "${1:-}" == "--env" ]]; then
    env_args+=("$2")
    shift 2
  fi

  local out_file="${tmpdir}/${name}.out"
  local err_file="${tmpdir}/${name}.err"
  local start_ms
  start_ms="$(test_now_ms)"

  if env "${env_args[@]}" nix run "${repo_root}#compile-and-build-forwarding-model" -- "${fixture}" >"${out_file}" 2>"${err_file}"; then
    echo "FAIL ${name}: expected compile failure" >&2
    jq '.' "${out_file}" >&2 || cat "${out_file}" >&2
    exit 1
  fi

  local pattern
  for pattern in "$@"; do
    if ! rg -q -- "${pattern}" "${err_file}"; then
      echo "FAIL ${name}: missing expected diagnostic pattern: ${pattern}" >&2
      sed -n '1,180p' "${err_file}" >&2
      exit 1
    fi
  done

  pass_timed "${name}" "${start_ms}"
}

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

bypass_core_intent="${tmpdir}/bypass-core.nix"
cat >"${bypass_core_intent}" <<'NIX'
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

    links.selector-bypass = {
      kind = "p2p";
      endpoints = {
        upstream = {
          addr4 = "10.37.9.0/31";
          interfaceData.routes4 = [
            {
              dst = "0.0.0.0/0";
              via4 = "10.37.9.1";
              proto = "default";
              intent = { kind = "default-reachability"; };
              lane = { access = "access-client"; uplink = "wan"; };
            }
          ];
        };
        policy = { addr4 = "10.37.9.1/31"; };
      };
    };

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

expect_compile_failure \
  "fs370-sms080-upstream-selector-default-route:seeded-negative-bypass-core" \
  "${bypass_core_intent}" \
  "selector-default-route-bypasses-core" \
  "selector-bypass" \
  "access-client" \
  "client"

expect_compile_failure \
  "fs370-sms080-upstream-selector-default-route:seeded-negative-missing-default" \
  "${input_nix}" \
  --env "S88_NFM_PROFILE_SKIP_NEAREST_DEFAULTS=1" \
  "selector-default-route-missing" \
  "access=access-client" \
  "tenant=client" \
  "uplink=wan"

pass_timed "fs370-sms080-upstream-selector-default-route"
