#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"

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

intent_path="${labs_path}/labs/lab-s-sigma/s-router-test-three-site/intent.nix"
nix run "${repo_root}#compile-and-build-forwarding-model" -- "${intent_path}" >"${output_json}"

OUTPUT_JSON="${output_json}" nix eval --impure --expr '
  let
    data = builtins.fromJSON (builtins.readFile (builtins.getEnv "OUTPUT_JSON"));
    nixos = data.enterprise.esp.site.nixos;
    hetz = data.enterprise.esp.site.hetz;

    hasDefault4 = routes:
      builtins.any (route: (route.dst or null) == "0.0.0.0/0") (routes.ipv4 or [ ]);
    hasDefault6 = routes:
      builtins.any (route: (route.dst or null) == "::/0") (routes.ipv6 or [ ]);

    nixosOverlay = nixos.nodes."nixos-router-core-nebula".interfaces."overlay-east-west".routes;
    nixosUnderlay = nixos.nodes."nixos-router-core-nebula".interfaces."p2p-nixos-router-core-nebula-nixos-router-upstream".routes;
    hetzUnderlay = hetz.nodes."hetz-router-nebula-core".interfaces."p2p-hetz-router-nebula-core-hetz-router-upstream".routes;
  in
    hasDefault4 nixosOverlay
    && hasDefault6 nixosOverlay
    && !(hasDefault4 nixosUnderlay)
    && !(hasDefault6 nixosUnderlay)
    && hasDefault4 hetzUnderlay
    && hasDefault6 hetzUnderlay
' | {
  if ! grep -qx true; then
    echo "FAIL overlay-core-default-stays-overlay: compiler overlay defaults must stay on overlay interfaces unless an explicit external-overlay-to-uplink relation allows local WAN egress" >&2
    exit 1
  fi
}

echo "PASS overlay-core-default-stays-overlay"
