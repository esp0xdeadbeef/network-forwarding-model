#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

archive_json="$(mktemp)"
trap 'rm -f "'"${archive_json}"'"' EXIT

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

intent_path="${labs_path}/examples/tri-site-dual-wan-overlay-integration-static/intent.nix"

output_json="$(mktemp)"
trap 'rm -f "'"${archive_json}"'" "'"${output_json}"'"' EXIT

nix run "${repo_root}#compile-and-build-forwarding-model" -- "${intent_path}" > "${output_json}"

OUTPUT_JSON="${output_json}" nix eval --impure --expr '
  let
    data = builtins.fromJSON (builtins.readFile (builtins.getEnv "OUTPUT_JSON"));
    siteB = data.enterprise.espbranch.site."site-b";
    policyIfaces = data.enterprise.espbranch.site."site-b".nodes."b-router-policy".interfaces;
    hostileEw = policyIfaces."p2p-b-router-policy-b-router-upstream-selector--access-b-router-access-hostile--uplink-east-west".routes;
    hasDst = routes: destination:
      builtins.any (route: (route.dst or null) == destination) (routes.ipv4 or [ ])
      || builtins.any (route: (route.dst or null) == destination) (routes.ipv6 or [ ]);
    hasDefault6 = routes:
      hasDst routes "::/0" || hasDst routes "0000:0000:0000:0000:0000:0000:0000:0000/0";
  in
    hasDst hostileEw "10.20.10.0/24"
    && hasDst hostileEw "fd42:dead:beef:0010:0000:0000:0000:0000/64"
    && hasDst hostileEw "0.0.0.0/0"
    && hasDefault6 hostileEw
    && (siteB.tenantPrefixOwners."6|fd42:dead:feed:0070:0000:0000:0000:0000/64".owner or null) == "b-router-access-hostile"
    && hasDst siteB.nodes."b-router-core-nebula".interfaces."p2p-b-router-core-nebula-b-router-upstream-selector".routes "fd42:dead:feed:0070:0000:0000:0000:0000/64"
' | {
  if ! grep -qx true; then
    echo "FAIL hostile-dns-east-west: hostile east-west policy lane must carry IPv4/IPv6 defaults toward the overlay core" >&2
    exit 1
  fi
}

echo "PASS hostile-dns-east-west"
