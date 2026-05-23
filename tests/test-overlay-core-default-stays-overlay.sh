#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
source "${repo_root}/tests/lib/timing.sh"

archive_json="$(mktemp)"
output_json="$(mktemp)"
trap 'rm -f "'"${archive_json}"'" "'"${output_json}"'"' EXIT

nix flake archive --json "path:${repo_root}" >"${archive_json}"

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
nix run "${repo_root}#compile-and-build-forwarding-model" -- "${intent_path}" >"${output_json}"

OUTPUT_JSON="${output_json}" nix eval --impure --expr '
  let
    data = builtins.fromJSON (builtins.readFile (builtins.getEnv "OUTPUT_JSON"));
    siteA = data.enterprise.esp0xdeadbeef.site."site-a";
    siteC = data.enterprise.esp0xdeadbeef.site."site-c";

    hasDefault4 = routes:
      builtins.any (route: (route.dst or null) == "0.0.0.0/0") (routes.ipv4 or [ ]);
    hasDefault6 = routes:
      builtins.any (route: (route.dst or null) == "::/0") (routes.ipv6 or [ ]);

    siteAOverlay = siteA.nodes."s-router-core-nebula".interfaces."overlay-east-west".routes;
    siteAUnderlay = siteA.nodes."s-router-core-nebula".interfaces."p2p-s-router-core-nebula-s-router-upstream-selector".routes;
    siteCUnderlay = siteC.nodes."c-router-nebula-core".interfaces."p2p-c-router-nebula-core-c-router-upstream-selector".routes;
  in
    !(hasDefault4 siteAOverlay)
    && !(hasDefault6 siteAOverlay)
    && hasDefault4 siteAUnderlay
    && hasDefault6 siteAUnderlay
    && hasDefault4 siteCUnderlay
    && hasDefault6 siteCUnderlay
' | {
  if ! grep -qx true; then
    echo "FAIL overlay-core-default-stays-overlay: examples must place executable overlay-underlay defaults on explicit underlay access, not on the overlay interface itself" >&2
    exit 1
  fi
}

pass_timed "overlay-core-default-stays-overlay"
