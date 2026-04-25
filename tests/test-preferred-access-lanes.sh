#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

output_json="${tmp_dir}/out.json"
archive_json="${tmp_dir}/archive.json"

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

intent="${labs_path}/examples/s-router-test-three-site/intent.nix"

(
  cd "${repo_root}"
  nix run .#compile-and-build-forwarding-model -- "${intent}" > "${output_json}"
)

  OUTPUT_JSON="${output_json}" nix eval --impure --expr '
  let
    data = builtins.fromJSON (builtins.readFile (builtins.getEnv "OUTPUT_JSON"));
    policy = data.enterprise.esp0xdeadbeef.site."site-a".nodes."s-router-policy-only";
    ifaces = policy.interfaces or { };

    routesOn = ifName: family:
      let
        iface = ifaces.${ifName} or { };
        routes = iface.routes or { };
      in
      if family == 4 then routes.ipv4 or [ ] else routes.ipv6 or [ ];

    hasRoute = ifName: dst: via:
      builtins.any (route: (route.dst or null) == dst && (route.via4 or route.via6 or null) == via) (routesOn ifName 4);
  in
    hasRoute "p2p-s-router-downstream-selector-s-router-policy-only--access-s-router-access-mgmt" "10.20.10.0/24" "10.10.0.22"
    && hasRoute "p2p-s-router-downstream-selector-s-router-policy-only--access-s-router-access-admin" "10.20.15.0/24" "10.10.0.14"
    && hasRoute "p2p-s-router-downstream-selector-s-router-policy-only--access-s-router-access-client" "10.20.20.0/24" "10.10.0.16"
    && hasRoute "p2p-s-router-downstream-selector-s-router-policy-only--access-s-router-access-dmz" "10.20.30.0/24" "10.10.0.20"
    && hasRoute "p2p-s-router-downstream-selector-s-router-policy-only--access-s-router-access-client2" "10.20.40.0/24" "10.10.0.18"
    && hasRoute "p2p-s-router-downstream-selector-s-router-policy-only--access-s-router-access-mgmt" "10.19.0.4/32" "10.10.0.22"
    && hasRoute "p2p-s-router-downstream-selector-s-router-policy-only--access-s-router-access-admin" "10.19.0.0/32" "10.10.0.14"
    && hasRoute "p2p-s-router-downstream-selector-s-router-policy-only--access-s-router-access-client" "10.19.0.1/32" "10.10.0.16"
    && hasRoute "p2p-s-router-downstream-selector-s-router-policy-only--access-s-router-access-client2" "10.19.0.2/32" "10.10.0.18"
    && hasRoute "p2p-s-router-downstream-selector-s-router-policy-only--access-s-router-access-dmz" "10.19.0.3/32" "10.10.0.20"
' >/dev/null || {
  echo "FAIL preferred-access-lanes" >&2
  exit 1
}

echo "PASS preferred-access-lanes"
