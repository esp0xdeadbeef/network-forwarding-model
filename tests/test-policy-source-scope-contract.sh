#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: SMT-NFM-POLICY-SOURCE-SCOPE-001
# GAMP-SCOPE: software-module-test

repo_root="$(git rev-parse --show-toplevel)"
source "${repo_root}/tests/lib/timing.sh"

archive_json="$(mktemp)"
work_dir="$(mktemp -d)"
trap 'rm -f "${archive_json}"; rm -rf "${work_dir}"' EXIT

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

output_json="${work_dir}/forwarding.json"
gron_txt="${work_dir}/forwarding.gron"
example_dir="${labs_path}/examples/s-router-overlay-dns-lane-policy"

start_ms="$(test_now_ms)"
nix run "${repo_root}#compile-and-build-forwarding-model" -- \
  "${example_dir}/intent.nix" >"${output_json}"
pass_timed "policy-source-scope-contract:compile" "${start_ms}"

gron "${output_json}" >"${gron_txt}"

require_gron() {
  local pattern="$1"
  if ! rg -q --fixed-strings "${pattern}" "${gron_txt}"; then
    echo "FAIL policy-source-scope-contract: missing gron line: ${pattern}" >&2
    exit 1
  fi
}

require_gron 'json.enterprise.espbranch.site["site-b"].tenantPrefixOwners["4|10.70.10.0/24"].owner = "b-router-access-hostile";'
require_gron 'json.enterprise.espbranch.site["site-b"].tenantPrefixOwners["6|source:/run/secrets/access-node-ipv6-prefix-espbranch-site-b-b-router-access-hostile"].owner = "b-router-access-hostile";'
require_gron 'json.enterprise.espbranch.site["site-b"].nodes["b-router-policy"].interfaces["p2p-b-router-policy-b-router-upstream-selector--access-b-router-access-hostile--uplink-east-west"].routes.ipv4[0].lane.access = "b-router-access-hostile";'
require_gron 'json.enterprise.espbranch.site["site-b"].nodes["b-router-policy"].interfaces["p2p-b-router-policy-b-router-upstream-selector--access-b-router-access-hostile--uplink-east-west"].routes.ipv4[0].lane.uplink = "east-west";'

jq -e '
  def route_has($access; $uplink; $dst):
    [.enterprise.espbranch.site["site-b"].nodes."b-router-policy".interfaces[]
      .routes.ipv4[]?, .enterprise.espbranch.site["site-b"].nodes."b-router-policy".interfaces[]
      .routes.ipv6[]?
      | select(
          (.policyOnly // false) == true
          and (.reason // "") == "policy-derived-default"
          and (.lane.access // "") == $access
          and (.lane.uplink // "") == $uplink
          and (.dst // "") == $dst
        )] | length > 0;
  .enterprise.espbranch.site["site-b"] as $site
  | ($site.tenantPrefixOwners["4|10.70.10.0/24"].owner == "b-router-access-hostile")
    and ($site.tenantPrefixOwners["6|fd42:dead:feed:0070:0000:0000:0000:0000/64"].owner == "b-router-access-hostile")
    and ($site.tenantPrefixOwners["6|source:/run/secrets/access-node-ipv6-prefix-espbranch-site-b-b-router-access-hostile"].owner == "b-router-access-hostile")
    and route_has("b-router-access-hostile"; "east-west"; "0.0.0.0/0")
    and route_has("b-router-access-hostile"; "east-west"; "::/0")
' "${output_json}" >/dev/null || {
  cat >&2 <<'EOF'
FAIL policy-source-scope-contract

NFM must emit both sides of the source-scoped policy-routing contract:
tenantPrefixOwners identify the source prefixes owned by the access node, and
policy-derived defaults identify the access/uplink lane that should use those
sources. CPM and renderers must not rediscover this from generated names.
EOF
  exit 1
}

pass_timed "policy-source-scope-contract"
