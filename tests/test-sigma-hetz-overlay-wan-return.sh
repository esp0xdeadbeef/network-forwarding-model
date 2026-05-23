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

intent_path="${labs_path}/labs/lab-s-sigma/s-router-test-three-site/intent.nix"

compile_start_ms="$(test_now_ms)"
nix run "${repo_root}#compile-and-build-forwarding-model" -- "${intent_path}" >"${output_json}"
pass_timed "sigma-hetz-overlay-wan-return:compile" "${compile_start_ms}"

jq -e '
  def hasRoute($dst; $via):
    any(.dst == $dst and ((.via4 // null) == $via or (.via6 // null) == $via));
  def peer4($link; $node):
    .enterprise.esp.site.hetz.links[$link].endpoints[$node].addr4 | split("/")[0];

  . as $root
  | $root.enterprise.esp.site.hetz.nodes."hetz-router-core"
    .interfaces."p2p-hetz-router-core-hetz-router-upstream".routes.ipv4
  | hasRoute(
      "10.20.70.0/24";
      ($root | peer4("p2p-hetz-router-core-hetz-router-upstream"; "hetz-router-upstream"))
    )
' "${output_json}" >/dev/null || {
  echo "FAIL sigma-hetz-overlay-wan-return: Hetz WAN core must route remote hostile IPv4 prefix back to upstream" >&2
  exit 1
}

echo "PASS sigma-hetz-overlay-wan-return"
