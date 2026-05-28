#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: SMT-NFM-HOSTILE-NO-WAN-001
# GAMP-SCOPE: software-module-test

repo_root="$(git rev-parse --show-toplevel)"
source "${repo_root}/tests/lib/timing.sh"

archive_json="$(mktemp)"
output_json="$(mktemp)"
trap 'rm -f "'"${archive_json}"'" "'"${output_json}"'"' EXIT

nix flake archive --json "path:${repo_root}" > "${archive_json}"

labs_path="$(
  ARCHIVE_JSON="${archive_json}" nix eval --impure --raw --expr '
    let
      archived = builtins.fromJSON (builtins.readFile (builtins.getEnv "ARCHIVE_JSON"));
      labs = archived.inputs."network-labs" or null;
      labsPath = if labs == null then null else labs.path or null;
    in
      if labsPath == null then
        throw "tests: missing archived network-labs input path"
      else
        labsPath
  '
)"

intent_path="${labs_path}/examples/s-router-overlay-dns-lane-policy/intent.nix"
nix run "${repo_root}#compile-and-build-forwarding-model" -- "${intent_path}" > "${output_json}"

OUTPUT_JSON="${output_json}" nix eval --impure --expr '
  let
    data = builtins.fromJSON (builtins.readFile (builtins.getEnv "OUTPUT_JSON"));
    siteB = data.enterprise.espbranch.site."site-b";
    hasDst = nodeName: destination:
      builtins.any (
        iface:
        builtins.any (route: (route.dst or null) == destination) (iface.routes.ipv4 or [ ])
        || builtins.any (route: (route.dst or null) == destination) (iface.routes.ipv6 or [ ])
      ) (builtins.attrValues (siteB.nodes.${nodeName}.interfaces or { }));
  in
    !(hasDst "b-router-core-simulated-isp" "10.70.10.0/24")
    && !(hasDst "b-router-core-simulated-isp" "fd42:dead:feed:0070:0000:0000:0000:0000/64")
    && hasDst "b-router-core-simulated-isp" "10.60.10.0/24"
    && hasDst "b-router-core-simulated-isp" "fd42:dead:feed:0010:0000:0000:0000:0000/64"
    && hasDst "b-router-core-nebula" "10.70.10.0/24"
    && hasDst "b-router-core-nebula" "fd42:dead:feed:0070:0000:0000:0000:0000/64"
' | {
  if ! grep -qx true; then
    echo "FAIL hostile-no-wan-core-reachability: hostile tenant prefixes must not be routed through the WAN/simulated-ISP core" >&2
    exit 1
  fi
}

pass_timed "hostile-no-wan-core-reachability"
