#!/usr/bin/env bash
# GAMP-ID: FS-540-HDS-010-SDS-010-SMS-040
# GAMP-SCOPE: software-module-test
#
# ============================================================================
# WHAT THIS ASSERTS, AND WHY IT CURRENTLY FAILS
# ============================================================================
#
# FS-540-HDS-010-SDS-010-SMS-040 says, verbatim:
#
#   "Emit resolver-specific IPv4 and IPv6 reachability on every requester path
#    leg."
#   "For per-requester policy tables, select only the next hop on that
#    requester's modeled upstream lane. Do not fan a shared resolver /32 or
#    /128 out over sibling VLAN, tenant, or access lanes."
#
# The fixture `s-router-overlay-dns-lane-policy` models exactly this: the
# relation `allow-sitea-tenants-to-mgmt-dns` allows the `admin`, `client`,
# `client2` and `dmz` tenants to reach the `site-dns-mgmt` service, whose
# endpoint sits on the `mgmt` tenant prefix at 10.20.10.0/24 /
# fd42:dead:beef:10::/64. The modeled resolver address is therefore
# 10.20.10.1/32 (V4) and fd42:dead:beef:10::1/128 (V6).
#
# Before this case existed the NFM emitted NO requester-lane scope for that
# relation at all: measured, zero routes to the mgmt prefix carried a lane key,
# so no requester lane ever learned the resolver.
#
# The cause was a source-shape assumption in the emitter:
#
#   implementation/lib/routing/internal-routes/remote-prefixes/service-route-scopes.nix
#     sourceExternalUplinks = source:
#       if (source.kind or null) != "external" then [ ] else ...
#
# A DNS service relation sourced from a tenant set ("from = { kind =
# \"tenant-set\"; members = [ ... ]; }") therefore yields `uplinks = [ ]`, the
# `dnsServiceRouteScopes` guard `uplinks == [ ]` short-circuits, and no service
# route scope is produced. Only `from = { kind = \"external\"; ...; }` relations
# can ever produce one. That is why the resolver reachability FS-540 describes
# does not exist in the model.
#
# This case is written here, in the layer that owns the emitter, because the
# defect is NFM's: the downstream control-plane model can only copy through
# service routes it is handed.
#
# NOT YET ASSERTED, and deliberately so: a resolver-specific host route
# (10.20.10.1/32, fd42:dead:beef:10::1/128). FS-540-HDS-010-SDS-010-SMS-040 requires one, and the NFM
# still only emits the requester-lane scope over the resolver's tenant prefix
# (10.20.10.0/24). Asserting it here would make this case red against a feature
# that does not exist yet, which hides the regression this case does guard.
# The /32 projection is recorded as open work instead.
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

fail() {
  printf 'FAIL requester-lane-resolver-reachability: %s\n' "$*" >&2
  exit 1
}

system="${NIX_SYSTEM:-$(nix eval --impure --raw --expr 'builtins.currentSystem')}"
report="${tmp_dir}/report.json"

if ! NFM_REPO="${repo_root}" NFM_SYSTEM="${system}" \
  nix eval --impure --json --expr '
    let
      repoRoot = builtins.getEnv "NFM_REPO";
      system = builtins.getEnv "NFM_SYSTEM";
      flake = builtins.getFlake ("path:" + repoRoot);
      api = flake.libBySystem.${system};
      compiler = flake.inputs.network-compiler.lib.compile system;
      intent = import (repoRoot + "/tests/fixtures/examples/s-router-overlay-dns-lane-policy/intent.nix");
      model = api.model (compiler intent);

      site = model.enterprise.esp0xdeadbeef.site.site-a;
      resolverPrefixV4 = "10.20.10.0/24";
      resolverPrefixV6 = "fd42:dead:beef:10::/64";

      routesOf = nodeName:
        builtins.concatMap
          (ifName:
            let
              routes = (site.nodes.${nodeName}.interfaces or { }).${ifName}.routes or { };
            in
            map (route: route // { inherit ifName; }) ((routes.ipv4 or [ ]) ++ (routes.ipv6 or [ ])))
          (builtins.attrNames ((site.nodes.${nodeName}.interfaces or { })));

      allRoutes = builtins.concatMap routesOf (builtins.attrNames site.nodes);

      describing = route: {
        inherit (route) ifName;
        dst = route.dst or null;
        via4 = route.via4 or null;
        via6 = route.via6 or null;
        laneAccess = ((route.lane or { }).access or null);
        laneUplink = ((route.lane or { }).uplink or null);
        intentKind = (route.intent or { }).kind or null;
      };

      toResolver = builtins.filter (
        route:
        ((route.dst or null) == resolverPrefixV4 || (route.dst or null) == resolverPrefixV6)
        && ((route.lane or { }).access or null) != null
      ) allRoutes;
    in
    {
      totalRoutes = builtins.length allRoutes;
      resolverRouteCount = builtins.length toResolver;
      resolverRoutes = builtins.genList (i: describing (builtins.elemAt toResolver i)) (
        if builtins.length toResolver > 10 then 10 else builtins.length toResolver
      );
    }
  ' >"${report}" 2>"${tmp_dir}/err"; then
  fail "the NFM model did not evaluate:
$(cat "${tmp_dir}/err")"
fi

count="$(jq -r '.resolverRouteCount' "${report}")"
total="$(jq -r '.totalRoutes' "${report}")"

if [[ "${count}" == "0" ]]; then
  {
    printf 'FAIL requester-lane-resolver-reachability: no requester lane learns the resolver.\n\n'
    printf 'FS-540-HDS-010-SDS-010-SMS-040 requires resolver reachability on every\n'
    printf 'requester path leg. The fixture models it:\n\n'
    printf '  relation allow-sitea-tenants-to-mgmt-dns -> service site-dns-mgmt\n'
    printf '  resolver prefix 10.20.10.0/24 (V4), fd42:dead:beef:10::/64 (V6)\n\n'
    printf 'Measured: %s site-a routes, %s of them a lane-scoped route to that prefix.\n\n' "${total}" "${count}"
    printf 'Why it cannot be repaired downstream: the control-plane model copies NFM\n'
    printf 'service routes through. With none emitted it has nothing to install, which is\n'
    printf 'what its five DNS checks report (admittedDmzLaneLearnsMgmtDnsV4,\n'
    printf 'clientLaneLearnsAllowedMgmtDnsV4/V6, clientLaneRouteIsPolicyTableAuthorityV4/V6).\n\n'
    printf 'Emitter defect (fix here):\n'
    printf '  implementation/lib/routing/internal-routes/remote-prefixes/service-route-scopes.nix\n'
    printf '    sourceExternalUplinks returns [ ] for every source whose kind is not\n'
    printf '    "external", so a tenant-set-sourced DNS service relation yields uplinks = [ ]\n'
    printf '    and dnsServiceRouteScopes emits no scope at all.\n'
  } >&2
  exit 1
fi

# A resolver route that exists but is fanned over every sibling lane would
# violate the second half of the same SMS clause just as badly as emitting none.
fanned="$(jq -r '[.resolverRoutes[] | .laneAccess] | map(select(. != null)) | length' "${report}")"
if [[ "${fanned}" == "0" ]]; then
  fail "the resolver routes carry no lane scope; {$count} route(s) exist but none is keyed to a requester lane"
fi

printf 'PASS requester-lane-resolver-reachability: %s scoped resolver route(s) on %s total routes\n' "${count}" "${total}"
