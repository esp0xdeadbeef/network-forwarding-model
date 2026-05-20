#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
source "${repo_root}/tests/lib/timing.sh"

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
tri_site_stderr="$(mktemp)"
s_router_stderr="$(mktemp)"
trap 'rm -f "'"${archive_json}"'" "'"${output_json}"'" "'"${s_router_output_json}"'" "'"${tri_site_stderr}"'" "'"${s_router_stderr}"'"' EXIT

tri_site_start_ms="$(test_now_ms)"
nix run "${repo_root}#compile-and-build-forwarding-model" -- "${intent_path}" > "${output_json}" 2>"${tri_site_stderr}" &
tri_site_pid="$!"

s_router_start_ms="$(test_now_ms)"
nix run "${repo_root}#compile-and-build-forwarding-model" -- "${s_router_intent_path}" > "${s_router_output_json}" 2>"${s_router_stderr}" &
s_router_pid="$!"

failed=0
if wait "${tri_site_pid}"; then
  pass_timed "hostile-dns-east-west:compile-tri-site" "${tri_site_start_ms}"
else
  failed=1
  cat "${tri_site_stderr}" >&2
  echo "FAIL hostile-dns-east-west:compile-tri-site" >&2
fi

if wait "${s_router_pid}"; then
  pass_timed "hostile-dns-east-west:compile-s-router" "${s_router_start_ms}"
else
  failed=1
  cat "${s_router_stderr}" >&2
  echo "FAIL hostile-dns-east-west:compile-s-router" >&2
fi

if [ "${failed}" -ne 0 ]; then
  exit 1
fi

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
    echo "FAIL hostile-dns-east-west: DNS-only hostile east-west policy lane must keep specific DNS reachability and executable east-west defaults" >&2
    exit 1
  fi
}

jq -e '
  .enterprise.espbranch.site["site-b"] as $site
  | ($site.nodes."b-router-upstream-selector".interfaces."p2p-b-router-core-nebula-b-router-upstream-selector".routes) as $hostileEw
  | ($site.nodes."b-router-core-nebula".interfaces."p2p-b-router-core-nebula-b-router-upstream-selector".routes) as $coreNebulaUpstream
  | ($site.nodes."b-router-access-branch".interfaces."p2p-b-router-access-branch-b-router-downstream-selector".routes) as $branchAccess
  | ([$hostileEw.ipv4[]? | select(.dst == "0.0.0.0/0" and .via4 == "10.50.0.4")] | length > 0)
    and ([$hostileEw.ipv6[]? | select((.dst == "::/0" or .dst == "0000:0000:0000:0000:0000:0000:0000:0000/0") and .via6 == "fd42:dead:feed:1000:0:0:0:4")] | length > 0)
    and ([$coreNebulaUpstream.ipv6[]?
      | select(
          .sourceFile == "/run/secrets/access-node-ipv6-prefix-espbranch-site-b-b-router-access-hostile"
          and .intent.kind == "runtime-routed-prefix-return"
          and .intent.source == "intent-routed-prefix"
          and .intent.accessNode == "b-router-access-hostile"
          and .via6 == "fd42:dead:feed:1000:0:0:0:5")] | length > 0)
    and ([$branchAccess.ipv6[]?
      | select(.sourceFile == "/run/secrets/access-node-ipv6-prefix-espbranch-site-b-b-router-access-hostile")] | length == 0)
' "${s_router_output_json}" >/dev/null || {
  echo "FAIL hostile-dns-east-west: s-router hostile east-west path must include NFM-owned runtime routed-prefix return without leaking it to unrelated access nodes" >&2
  exit 1
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

pass_timed "hostile-dns-east-west"
