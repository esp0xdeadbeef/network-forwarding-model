#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: SMT-NFM-OVERLAY-UPLINK-DEFAULT-001
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
      if labsPath == null then
        throw "tests: missing archived network-labs input path"
      else
        labsPath
  '
)"

intent_path="${labs_path}/examples/s-router-overlay-dns-lane-policy/intent.nix"
nix run "${repo_root}#compile-and-build-forwarding-model" -- "${intent_path}" >"${output_json}"

jq -e '
  def has_default($routes; $dst; $via; $access; $uplink):
    [ $routes[]?
      | select(.dst == $dst)
      | select((.via4 // .via6 // "") == $via)
      | select(.intent.kind == "default-reachability")
      | select(.reason == "policy-derived-default")
      | select(.policyOnly == true)
      | select(.lane.access == $access)
      | select(.lane.uplink == $uplink)
    ] | length == 1;

  .enterprise.esp0xdeadbeef.site["site-c"] as $site
  | ($site.nodes."c-router-policy".interfaces."p2p-c-router-policy-c-router-upstream-selector--access-c-router-access-client--uplink-east-west".routes) as $policyEastWest
  | ($site.nodes."c-router-upstream-selector".interfaces."p2p-c-router-nebula-core-c-router-upstream-selector".routes) as $selectorEastWest
  | has_default(($policyEastWest.ipv4 // []); "0.0.0.0/0"; "10.80.0.13"; "c-router-access-client"; "east-west")
    and has_default(($policyEastWest.ipv6 // []); "::/0"; "fd42:dead:cafe:1000:0:0:0:d"; "c-router-access-client"; "east-west")
    and has_default(($selectorEastWest.ipv4 // []); "0.0.0.0/0"; "10.80.0.10"; "c-router-access-client"; "east-west")
    and has_default(($selectorEastWest.ipv6 // []); "::/0"; "fd42:dead:cafe:1000:0:0:0:a"; "c-router-access-client"; "east-west")
' "${output_json}" >/dev/null || {
  cat >&2 <<'EOF'
FAIL overlay-access-uplink-defaults-without-core-default

An allowed access -> external overlay relation is executable forwarding intent
even when the overlay core uplink does not advertise 0/0 in its uplink prefix
list. NFM must emit lane-specific default-reachability on the policy and
upstream-selector stages so CPM/renderers do not invent overlay route defaults
from role names or rendered link names.
EOF
  exit 1
}

pass_timed "overlay-access-uplink-defaults-without-core-default"
