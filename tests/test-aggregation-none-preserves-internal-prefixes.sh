#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: SMT-NFM-FS940-AGGREGATION-NONE-001
# GAMP-SCOPE: software-module-test

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

start_ms="$(test_now_ms)"
nix run "${repo_root}#compile-and-build-forwarding-model" -- "${labs_path}/examples/multi-wan/intent.nix" >"${output_json}"
pass_timed "aggregation-none-preserves-internal-prefixes:compile" "${start_ms}"

jq -e '
  .enterprise.esp0xdeadbeef.site."site-a" as $site
  | [
      $site.nodes."s-router-core-isp-a"
        .interfaces."p2p-s-router-core-isp-a-s-router-upstream-selector"
        .routes.ipv6[]?
      | select(
          .dst == "fd42:dead:beef:1900:0:0:0:5/128"
          and .via6 == "fd42:dead:beef:1000:0:0:0:5"
          and .proto == "internal"
          and .intent.kind == "internal-reachability"
        )
    ] | length == 1
' "${output_json}" >/dev/null || {
  cat >&2 <<'EOF'
FAIL aggregation-none-preserves-internal-prefixes

With aggregation.mode = "none", the forwarding model must not collapse exact
internal IPv6 host-prefix reachability into a broader summarized prefix during
route-group construction or route normalization.
EOF
  jq '
    .enterprise.esp0xdeadbeef.site."site-a".nodes."s-router-core-isp-a"
      .interfaces."p2p-s-router-core-isp-a-s-router-upstream-selector"
      .routes.ipv6
  ' "${output_json}" >&2
  exit 1
}

pass_timed "aggregation-none-preserves-internal-prefixes"
