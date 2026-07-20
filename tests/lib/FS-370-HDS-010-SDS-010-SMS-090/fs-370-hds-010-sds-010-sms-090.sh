#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-370-HDS-010-SDS-010-SMS-090
# GAMP-SCOPE: software-module-test
#
# Focused construction test: core return-path routing.
# SMS-090 requires the core node to have return routes for tenant subnets
# pointing toward the upstream-selector (return path after NAT).
#
# Seeded negatives:
#   - Core has no route for tenant subnets
#   - Core tenant route via4 is null (routing broken)
#   - Missing core return route with internet egress requirement fails closed
#   - Core return route on a non-upstream-selector interface fails closed

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
        trafficType = "any"; returnBehavior = "symmetric"; action = "allow"; }
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
pass_timed "fs370-sms090-core-return-path-routing:compile" "${start_ms}"

# Predicate 1: Core node has internal-reachability route for tenant subnet with non-null via4
jq -e '
  .enterprise.acme.site.ams as $site
  | $site.nodes["core-wan"] as $core
  | def tenant_return:
      ($core.interfaces // {})
      | to_entries[]
      | .value.routes.ipv4[]?
      | select(.dst == "10.37.20.0/24" and .intent.kind == "internal-reachability");
  any(tenant_return; .via4 != null)
' "${output_json}" >/dev/null || {
  echo "FAIL fs370-sms090: core node must have internal-reachability route for tenant subnet 10.37.20.0/24 with non-null via4" >&2
  jq '[.enterprise.acme.site.ams.nodes["core-wan"].interfaces | to_entries[] | .value.routes.ipv4[]? | select(.dst == "10.37.20.0/24") | {dst, intent_kind: .intent.kind, via4}]' "${output_json}" >&2
  exit 1
}

# Predicate 2: Tenant return route via4 is in the p2p subnet (not a WAN address)
jq -e '
  .enterprise.acme.site.ams as $site
  | $site.nodes["core-wan"] as $core
  | def tenant_via:
      ($core.interfaces // {})
      | to_entries[]
      | .value.routes.ipv4[]?
      | select(.dst == "10.37.20.0/24")
      | .via4;
  any(tenant_via; test("^10\\.37\\."))
' "${output_json}" >/dev/null || {
  echo "FAIL fs370-sms090: core tenant return route via4 must be in the p2p subnet (10.37.x.x), not a WAN address" >&2
  jq '[.enterprise.acme.site.ams.nodes["core-wan"].interfaces | to_entries[] | .value.routes.ipv4[]? | select(.dst == "10.37.20.0/24") | {dst, via4}]' "${output_json}" >&2
  exit 1
}

# Seeded negative 1: Verify both forward and return paths exist
jq -e '
  .enterprise.acme.site.ams as $site
  | def us_forward:
      ($site.nodes["upstream"].interfaces // {})
      | to_entries[]
      | .value.routes.ipv4[]?
      | select(.intent.kind == "default-reachability" and .via4 != null);
  def core_return:
      ($site.nodes["core-wan"].interfaces // {})
      | to_entries[]
      | .value.routes.ipv4[]?
      | select(.dst == "10.37.20.0/24" and .via4 != null);
  any(us_forward; true) and any(core_return; true)
' "${output_json}" >/dev/null || {
  echo "FAIL fs370-sms090: both forward (upstream→core default) and return (core→upstream tenant) paths must exist" >&2
  exit 1
}

# Seeded negative 2: Core must have at least one route (not empty forwarding table)
jq -e '
  .enterprise.acme.site.ams as $site
  | $site.nodes["core-wan"] as $core
  | def all_routes:
      ($core.interfaces // {})
      | to_entries[]
      | .value.routes.ipv4[]?;
  [all_routes] | length > 0
' "${output_json}" >/dev/null || {
  echo "FAIL fs370-sms090: core node must have at least one route in its forwarding table" >&2
  exit 1
}

wrong_return_interface_intent="${tmpdir}/wrong-return-interface.nix"
cat >"${wrong_return_interface_intent}" <<'NIX'
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
        trafficType = "any"; returnBehavior = "symmetric"; action = "allow"; }
    ];

    transit.ordering = [
      [ "access-client" "downstream" ]
      [ "downstream" "policy" ]
      [ "policy" "upstream" ]
      [ "upstream" "core-wan" ]
    ];

    links.core-egress-wrong = {
      kind = "p2p";
      endpoints = {
        core-wan = {
          addr4 = "10.37.9.0/31";
          interfaceData.routes4 = [
            {
              dst = "10.37.20.0/24";
              via4 = "10.37.9.1";
              proto = "internal";
              intent = { kind = "internal-reachability"; };
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
  "fs370-sms090-core-return-path-routing:seeded-negative-wrong-interface" \
  "${wrong_return_interface_intent}" \
  "core-return-route-wrong-interface" \
  "core-egress-wrong" \
  "tenant=client" \
  "prefix=10\\.37\\.20\\.0/24"

expect_compile_failure \
  "fs370-sms090-core-return-path-routing:seeded-negative-missing-return" \
  "${input_nix}" \
  --env "S88_NFM_PROFILE_SKIP_INTERNAL_ROUTES=1" \
  "core-return-route-missing" \
  "tenant=client" \
  "prefix=10\\.37\\.20\\.0/24" \
  "uplink=wan"

pass_timed "fs370-sms090-core-return-path-routing"
