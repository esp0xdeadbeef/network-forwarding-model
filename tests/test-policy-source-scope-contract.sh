#!/usr/bin/env bash
set -euo pipefail

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
lab_dir="${labs_path}/labs/lab-s-sigma/s-router-test-three-site"

start_ms="$(test_now_ms)"
nix run "${repo_root}#compile-and-build-forwarding-model" -- \
  "${lab_dir}/intent.nix" >"${output_json}"
pass_timed "policy-source-scope-contract:compile" "${start_ms}"

gron "${output_json}" >"${gron_txt}"

require_gron() {
  local pattern="$1"
  if ! rg -q --fixed-strings "${pattern}" "${gron_txt}"; then
    echo "FAIL policy-source-scope-contract: missing gron line: ${pattern}" >&2
    exit 1
  fi
}

require_gron 'json.enterprise.esp.site.nixos.tenantPrefixOwners["4|10.20.70.0/24"].owner = "nixos-router-access-hostile";'
require_gron 'json.enterprise.esp.site.nixos.tenantPrefixOwners["6|source:/run/secrets/access-node-ipv6-prefix-esp-nixos-router-access-hostile"].owner = "nixos-router-access-hostile";'
require_gron 'json.enterprise.esp.site.nixos.nodes["nixos-router-policy"].interfaces["p2p-nixos-router-policy-nixos-router-upstream--access-nixos-router-access-hostile--uplink-east-west"].routes.ipv4[0].lane.access = "nixos-router-access-hostile";'
require_gron 'json.enterprise.esp.site.nixos.nodes["nixos-router-policy"].interfaces["p2p-nixos-router-policy-nixos-router-upstream--access-nixos-router-access-hostile--uplink-east-west"].routes.ipv4[0].lane.uplink = "east-west";'

jq -e '
  def route_has($access; $uplink; $dst):
    [.enterprise.esp.site.nixos.nodes."nixos-router-policy".interfaces[]
      .routes.ipv4[]?, .enterprise.esp.site.nixos.nodes."nixos-router-policy".interfaces[]
      .routes.ipv6[]?
      | select(
          (.policyOnly // false) == true
          and (.reason // "") == "policy-derived-default"
          and (.lane.access // "") == $access
          and (.lane.uplink // "") == $uplink
          and (.dst // "") == $dst
        )] | length > 0;
  .enterprise.esp.site.nixos as $site
  | ($site.tenantPrefixOwners["4|10.20.70.0/24"].owner == "nixos-router-access-hostile")
    and ($site.tenantPrefixOwners["6|fd42:dead:beef:0070:0000:0000:0000:0000/64"].owner == "nixos-router-access-hostile")
    and ($site.tenantPrefixOwners["6|source:/run/secrets/access-node-ipv6-prefix-esp-nixos-router-access-hostile"].owner == "nixos-router-access-hostile")
    and route_has("nixos-router-access-hostile"; "east-west"; "0.0.0.0/0")
    and route_has("nixos-router-access-hostile"; "east-west"; "::/0")
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
