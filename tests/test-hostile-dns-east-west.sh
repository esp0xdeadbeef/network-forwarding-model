#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"

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
s_router_intent_path="${labs_path}/examples/s-router-overlay-dns-lane-policy/intent.nix"

output_json="$(mktemp)"
s_router_output_json="$(mktemp)"
trap 'rm -f "'"${archive_json}"'" "'"${output_json}"'" "'"${s_router_output_json}"'"' EXIT

nix run "${repo_root}#compile-and-build-forwarding-model" -- "${intent_path}" > "${output_json}"
nix run "${repo_root}#compile-and-build-forwarding-model" -- "${s_router_intent_path}" > "${s_router_output_json}"

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

OUTPUT_JSON="${s_router_output_json}" nix eval --impure --expr '
  let
    data = builtins.fromJSON (builtins.readFile (builtins.getEnv "OUTPUT_JSON"));
    siteB = data.enterprise.espbranch.site."site-b";
    upstreamIfaces = siteB.nodes."b-router-upstream-selector".interfaces;
    hostileEw =
      upstreamIfaces."p2p-b-router-core-nebula-b-router-upstream-selector".routes;
    hasRoute = routes: destination: gateway:
      builtins.any (
        route:
        (route.dst or null) == destination
        && ((route.via4 or null) == gateway || (route.via6 or null) == gateway)
      ) ((routes.ipv4 or [ ]) ++ (routes.ipv6 or [ ]));
    hasDefault6 = routes: gateway:
      hasRoute routes "::/0" gateway
      || hasRoute routes "0000:0000:0000:0000:0000:0000:0000:0000/0" gateway;
  in
    hasRoute hostileEw "0.0.0.0/0" "10.50.0.4"
    && hasDefault6 hostileEw "fd42:dead:feed:1000:0:0:0:4"
' | {
  if ! grep -qx true; then
    echo "FAIL hostile-dns-east-west: s-router hostile upstream-selector east-west policy default must be installed on the Nebula core link" >&2
    exit 1
  fi
}

OUTPUT_JSON="${s_router_output_json}" nix eval --impure --expr '
  let
    data = builtins.fromJSON (builtins.readFile (builtins.getEnv "OUTPUT_JSON"));
    siteC = data.enterprise.esp0xdeadbeef.site."site-c";
    policyIfaces = siteC.nodes."c-router-policy".interfaces;
    clientEw =
      policyIfaces."p2p-c-router-policy-c-router-upstream-selector--access-c-router-access-client--uplink-east-west".routes;
    clientWan =
      policyIfaces."p2p-c-router-policy-c-router-upstream-selector--access-c-router-access-client--uplink-wan".routes;
    hasRoute = routes: destination: gateway:
      builtins.any (
        route:
        (route.dst or null) == destination
        && ((route.via4 or null) == gateway || (route.via6 or null) == gateway)
      ) ((routes.ipv4 or [ ]) ++ (routes.ipv6 or [ ]));
  in
    !(hasRoute clientEw "0.0.0.0/0" "10.80.0.13")
    && hasRoute clientWan "0.0.0.0/0" "10.80.0.15"
' | {
  if ! grep -qx true; then
    echo "FAIL hostile-dns-east-west: site-c client public IPv4 default must prefer WAN, not east-west overlay" >&2
    exit 1
  fi
}

echo "PASS hostile-dns-east-west"
