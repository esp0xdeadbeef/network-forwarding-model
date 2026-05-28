#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
source "${repo_root}/tests/lib/timing.sh"

archive_json="$(mktemp)"
output_json="$(mktemp)"
trap 'rm -f "${archive_json}" "${output_json}"' EXIT

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

intent_path="${labs_path}/examples/tri-site-s-router-overlay-egress/intent.nix"

compile_start_ms="$(test_now_ms)"
nix run "${repo_root}#compile-and-build-forwarding-model" -- "${intent_path}" >"${output_json}"
pass_timed "overlay-core-local-hostile-return-routes:compile" "${compile_start_ms}"

jq -e '
  def is_hostile_ula:
    . == "fd42:dead:beef:70::/64"
    or . == "fd42:dead:beef:0070:0000:0000:0000:0000/64";

  .enterprise.esp.site.home as $site
  | $site.nodes."home-example-router-core-nebula"
    .interfaces."p2p-home-example-router-core-nebula-home-example-router-upstream"
    .routes as $routes
  | any($routes.ipv4[]?;
      .dst == "10.20.70.0/24"
      and .via4 == "10.10.0.17"
      and .proto == "internal"
      and .intent.kind == "internal-reachability")
    and any($routes.ipv6[]?;
      (.dst | is_hostile_ula)
      and .via6 == "fd42:dead:beef:1000:0:0:0:11"
      and .proto == "internal"
      and .intent.kind == "internal-reachability")
    and any($routes.ipv6[]?;
      .sourceFile == "/run/secrets/access-node-ipv6-prefix-esp-home-example-router-access-hostile"
      and .via6 == "fd42:dead:beef:1000:0:0:0:11"
      and .proto == "internal"
      and .intent.kind == "runtime-routed-prefix-return")
' "${output_json}" >/dev/null || {
  cat >&2 <<'EOF'
FAIL overlay-core-local-hostile-return-routes

The s-router local overlay edge must route local hostile IPv4, hostile ULA, and
runtime delegated hostile GUA prefixes back to the upstream selector over the
real p2p leg. The virtual underlay-access edge used for overlay bootstrap must
not make internal return-prefix routes disappear or loop back into the overlay.
EOF
  jq '
    .enterprise.esp.site.home.nodes."home-example-router-core-nebula"
      .interfaces."p2p-home-example-router-core-nebula-home-example-router-upstream"
      .routes
  ' "${output_json}" >&2
  exit 1
}

pass_timed "overlay-core-local-hostile-return-routes"
