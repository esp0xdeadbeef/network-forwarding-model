#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: SMT-NFM-DNS-REQUESTER-LANE-001
# GAMP-SCOPE: software-module-test

repo_root="$(git rev-parse --show-toplevel)"
source "${repo_root}/tests/lib/timing.sh"

archive_json="$(mktemp)"
output_json="$(mktemp)"
stderr_log="$(mktemp)"
trap 'rm -f "${archive_json}" "${output_json}" "${stderr_log}"' EXIT

nix flake archive --json "path:${repo_root}" >"${archive_json}"

labs_path="$(
  ARCHIVE_JSON="${archive_json}" nix eval --impure --raw --expr '
    let
      archived = builtins.fromJSON (builtins.readFile (builtins.getEnv "ARCHIVE_JSON"));
      labs = archived.inputs."network-labs" or null;
      labsPath = if labs == null then null else labs.path or null;
    in
      if labsPath == null then throw "tests: missing archived network-labs input path" else labsPath
  '
)"

intent="${labs_path}/examples/s-router-overlay-dns-lane-policy/intent.nix"

start_ms="$(test_now_ms)"
nix run "${repo_root}#compile-and-build-forwarding-model" -- "${intent}" >"${output_json}" 2>"${stderr_log}" || {
  cat "${stderr_log}" >&2
  echo "FAIL dns-service-requester-lane-routes: compile" >&2
  exit 1
}
pass_timed "dns-service-requester-lane-routes:compile" "${start_ms}"

jq -e '
  .enterprise.esp0xdeadbeef.site["site-a"] as $site
  | "s-router-access-client" as $client
  | "east-west" as $uplink
  | "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-client--uplink-east-west" as $clientIface
  | ($site.nodes."s-router-upstream-selector".interfaces[$clientIface].routes) as $clientRoutes
  | def scoped_dns_routes:
      [
        $site.nodes."s-router-upstream-selector".interfaces
        | to_entries[]
        | .key as $iface
        | (.value.routes.ipv4[]?, .value.routes.ipv6[]?)
        | select(
            (.dst == "10.20.10.0/24"
              or .dst == "fd42:dead:beef:0010:0000:0000:0000:0000/64")
            and (.lane.uplink // null) == $uplink
          )
        | { iface: $iface, route: . }
      ];
    def client_has($dst):
      [
        ($clientRoutes.ipv4[]?, $clientRoutes.ipv6[]?)
        | select(
            .dst == $dst
            and (.intent.kind // "") == "internal-reachability"
            and (.lane.access // null) == $client
            and (.lane.uplink // null) == $uplink
          )
      ] | length == 1;
    client_has("10.20.10.0/24")
    and client_has("fd42:dead:beef:0010:0000:0000:0000:0000/64")
    and all(scoped_dns_routes[];
      (.route.lane.access == $client and .iface == $clientIface)
    )
' "${output_json}" >/dev/null || {
  cat >&2 <<'EOF'
FAIL dns-service-requester-lane-routes

NFM must emit Site A management DNS service-prefix reachability on the
requester lane that enters from east-west through s-router-access-client. CPM
and renderers must not clone these DNS service routes from the management
provider lane or infer requester scope from interface names.
EOF
  exit 1
}

pass_timed "dns-service-requester-lane-routes"
