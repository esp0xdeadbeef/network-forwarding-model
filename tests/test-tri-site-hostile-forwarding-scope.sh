#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
source "${repo_root}/tests/lib/timing.sh"

archive_json="$(mktemp)"
output_json="$(mktemp)"
actual_defaults="$(mktemp)"
expected_defaults="$(mktemp)"
actual_overlay_routes="$(mktemp)"
expected_overlay_routes="$(mktemp)"
trap 'rm -f "'"${archive_json}"'" "'"${output_json}"'" "'"${actual_defaults}"'" "'"${expected_defaults}"'" "'"${actual_overlay_routes}"'" "'"${expected_overlay_routes}"'"' EXIT

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

intent_path="${labs_path}/examples/tri-site-dual-wan-overlay-integration-static/intent.nix"

compile_start_ms="$(test_now_ms)"
nix run "${repo_root}#compile-and-build-forwarding-model" -- "${intent_path}" >"${output_json}"
pass_timed "tri-site-hostile-forwarding-scope:compile" "${compile_start_ms}"

site_jq='.enterprise.espbranch.site["site-b"]'

fail() {
  printf 'FAIL tri-site-hostile-forwarding-scope: %s\n' "$*" >&2
  exit 1
}

assert_jq() {
  local description="$1"
  local expr="$2"

  if ! jq -e "${site_jq} | ${expr}" "${output_json}" >/dev/null; then
    fail "${description}"
  fi
}

assert_route() {
  local node="$1"
  local iface="$2"
  local dst="$3"
  local via="$4"

  jq -e \
    --arg node "${node}" \
    --arg iface "${iface}" \
    --arg dst "${dst}" \
    --arg via "${via}" \
    "${site_jq}
      | .nodes[\$node].interfaces[\$iface] as \$ifaceData
      | ((\$ifaceData.routes.ipv4 // []) + (\$ifaceData.routes.ipv6 // []))
      | any(.dst == \$dst and ((.via4 // null) == \$via or (.via6 // null) == \$via))" \
    "${output_json}" >/dev/null || fail "missing route: ${node} ${iface} ${dst} via ${via}"
}

assert_connected() {
  local node="$1"
  local iface="$2"
  local dst="$3"

  jq -e \
    --arg node "${node}" \
    --arg iface "${iface}" \
    --arg dst "${dst}" \
    "${site_jq}
      | .nodes[\$node].interfaces[\$iface] as \$ifaceData
      | ((\$ifaceData.routes.ipv4 // []) + (\$ifaceData.routes.ipv6 // []))
      | any(.dst == \$dst and .proto == \"connected\")" \
    "${output_json}" >/dev/null || fail "missing connected route: ${node} ${iface} ${dst}"
}

assert_iface_addr() {
  local node="$1"
  local iface="$2"
  local addr4="$3"
  local addr6="$4"

  jq -e \
    --arg node "${node}" \
    --arg iface "${iface}" \
    --arg addr4 "${addr4}" \
    --arg addr6 "${addr6}" \
    "${site_jq}
      | .nodes[\$node].interfaces[\$iface]
      | (.addr4 == \$addr4 and .addr6 == \$addr6)" \
    "${output_json}" >/dev/null || fail "wrong interface addresses: ${node} ${iface}"
}

assert_loopback() {
  local node="$1"
  local addr4="$2"
  local addr6="$3"

  jq -e \
    --arg node "${node}" \
    --arg addr4 "${addr4}" \
    --arg addr6 "${addr6}" \
    "${site_jq} | .nodes[\$node].loopback == { ipv4: \$addr4, ipv6: \$addr6 }" \
    "${output_json}" >/dev/null || fail "wrong loopback: ${node}"
}

assert_no_bgp_in_nfm() {
  jq -e '
    [
      paths(scalars) as $p
      | select(($p | map(tostring) | join(".")) | test("(^|\\.)bgp($|\\.)|(^|\\.)asn($|\\.)|routerId"; "i"))
      | $p
    ]
    | length == 0
  ' "${output_json}" >/dev/null || fail "NFM output unexpectedly contains BGP realization facts"
}

assert_overlay_interface() {
  local node="$1"
  local iface="$2"
  local overlay="$3"

  jq -e \
    --arg node "${node}" \
    --arg iface "${iface}" \
    --arg overlay "${overlay}" \
    "${site_jq}
      | .nodes[\$node].interfaces[\$iface]
      | .kind == \"overlay\"
        and .logical == true
        and .virtual == true
        and .overlay == \$overlay
        and .addr4 == null
        and .addr6 == null" \
    "${output_json}" >/dev/null || fail "wrong logical overlay interface: ${node} ${iface}"
}

assert_jq "static intent must retain hostile any-to-wan relation" '
  .trafficPaths
  | map(select(.relationId == "allow-hostile-to-wan"))
  | length == 1
'

assert_jq "static intent must retain only DNS hostile east-west relation" '
  .trafficPaths
  | map(select(.relationId == "allow-hostile-dns-to-east-west"))
  | length == 1
'

assert_jq "static intent must not compile hostile any east-west path" '
  .trafficPaths
  | all(
      (select(
        .action == "allow"
        and .trafficType == "any"
        and (.destination.kind // null) == "external"
        and (.destination.name // null) == "east-west"
        and ((.source.members // []) | index("hostile"))
      ) | not)
    )
'

assert_no_bgp_in_nfm

assert_loopback "b-router-access-branch" "10.59.0.0/32" "fd42:dead:feed:1900:0:0:0:0/128"
assert_loopback "b-router-access-hostile" "10.59.0.1/32" "fd42:dead:feed:1900:0:0:0:1/128"
assert_loopback "b-router-core-nebula" "10.59.0.2/32" "fd42:dead:feed:1900:0:0:0:2/128"
assert_loopback "b-router-core-simulated-isp" "10.59.0.3/32" "fd42:dead:feed:1900:0:0:0:3/128"
assert_loopback "b-router-downstream-selector" "10.59.0.4/32" "fd42:dead:feed:1900:0:0:0:4/128"
assert_loopback "b-router-policy" "10.59.0.5/32" "fd42:dead:feed:1900:0:0:0:5/128"
assert_loopback "b-router-upstream-selector" "10.59.0.6/32" "fd42:dead:feed:1900:0:0:0:6/128"

assert_iface_addr "b-router-access-hostile" "tenant-hostile" "10.70.10.1/24" "fd42:dead:feed:70:0:0:0:1/64"
assert_iface_addr "b-router-access-hostile" "p2p-b-router-access-hostile-b-router-downstream-selector" "10.50.0.2/31" "fd42:dead:feed:1000:0:0:0:2/127"
assert_iface_addr "b-router-downstream-selector" "p2p-b-router-access-hostile-b-router-downstream-selector" "10.50.0.3/31" "fd42:dead:feed:1000:0:0:0:3/127"
assert_iface_addr "b-router-downstream-selector" "p2p-b-router-downstream-selector-b-router-policy--access-b-router-access-hostile" "10.50.0.10/31" "fd42:dead:feed:1000:0:0:0:a/127"
assert_iface_addr "b-router-policy" "p2p-b-router-downstream-selector-b-router-policy--access-b-router-access-hostile" "10.50.0.11/31" "fd42:dead:feed:1000:0:0:0:b/127"
assert_iface_addr "b-router-policy" "p2p-b-router-policy-b-router-upstream-selector--access-b-router-access-hostile--uplink-wan" "10.50.0.18/31" "fd42:dead:feed:1000:0:0:0:12/127"
assert_iface_addr "b-router-upstream-selector" "p2p-b-router-policy-b-router-upstream-selector--access-b-router-access-hostile--uplink-wan" "10.50.0.19/31" "fd42:dead:feed:1000:0:0:0:13/127"
assert_iface_addr "b-router-policy" "p2p-b-router-policy-b-router-upstream-selector--access-b-router-access-hostile--uplink-east-west" "10.50.0.16/31" "fd42:dead:feed:1000:0:0:0:10/127"
assert_iface_addr "b-router-upstream-selector" "p2p-b-router-policy-b-router-upstream-selector--access-b-router-access-hostile--uplink-east-west" "10.50.0.17/31" "fd42:dead:feed:1000:0:0:0:11/127"
assert_iface_addr "b-router-upstream-selector" "p2p-b-router-core-simulated-isp-b-router-upstream-selector" "10.50.0.7/31" "fd42:dead:feed:1000:0:0:0:7/127"
assert_iface_addr "b-router-core-simulated-isp" "p2p-b-router-core-simulated-isp-b-router-upstream-selector" "10.50.0.6/31" "fd42:dead:feed:1000:0:0:0:6/127"
assert_iface_addr "b-router-upstream-selector" "p2p-b-router-core-nebula-b-router-upstream-selector" "10.50.0.5/31" "fd42:dead:feed:1000:0:0:0:5/127"
assert_iface_addr "b-router-core-nebula" "p2p-b-router-core-nebula-b-router-upstream-selector" "10.50.0.4/31" "fd42:dead:feed:1000:0:0:0:4/127"
assert_overlay_interface "b-router-core-nebula" "overlay-east-west" "east-west"

jq -e "${site_jq} |"'
  .overlayAddressPools."east-west".ipv4.prefix == "100.96.10.0/24"
  and .overlayAddressPools."east-west".ipv4.perNodePrefixLength == 32
  and .overlayAddressPools."east-west".ipv4.offsetStart == 10
  and .overlayAddressPools."east-west".ipv6.prefix == "fd42:dead:beef:ee::/64"
  and .overlayAddressPools."east-west".ipv6.perNodePrefixLength == 128
  and .overlayAddressPools."east-west".ipv6.offsetStart == 10
' "${output_json}" >/dev/null || fail "NFM did not preserve intent-owned overlay address pools"

assert_connected "b-router-access-hostile" "tenant-hostile" "10.70.10.0/24"
assert_connected "b-router-access-hostile" "tenant-hostile" "fd42:dead:feed:0070:0000:0000:0000:0000/64"
assert_connected "b-router-core-simulated-isp" "p2p-b-router-core-simulated-isp-b-router-upstream-selector" "10.50.0.6/31"
assert_connected "b-router-core-simulated-isp" "p2p-b-router-core-simulated-isp-b-router-upstream-selector" "fd42:dead:feed:1000:0000:0000:0000:0006/127"
assert_connected "b-router-core-nebula" "p2p-b-router-core-nebula-b-router-upstream-selector" "10.50.0.4/31"
assert_connected "b-router-core-nebula" "p2p-b-router-core-nebula-b-router-upstream-selector" "fd42:dead:feed:1000:0000:0000:0000:0004/127"

# Hypothetical hostile traceroute toward a public IPv4/IPv6 destination:
# hostile client -> access-hostile -> downstream -> policy -> upstream -> local WAN core.
assert_route "b-router-access-hostile" "p2p-b-router-access-hostile-b-router-downstream-selector" "0.0.0.0/0" "10.50.0.3"
assert_route "b-router-access-hostile" "p2p-b-router-access-hostile-b-router-downstream-selector" "::/0" "fd42:dead:feed:1000:0:0:0:3"
assert_route "b-router-downstream-selector" "p2p-b-router-downstream-selector-b-router-policy--access-b-router-access-hostile" "0.0.0.0/0" "10.50.0.11"
assert_route "b-router-downstream-selector" "p2p-b-router-downstream-selector-b-router-policy--access-b-router-access-hostile" "::/0" "fd42:dead:feed:1000:0:0:0:b"
assert_route "b-router-policy" "p2p-b-router-policy-b-router-upstream-selector--access-b-router-access-hostile--uplink-wan" "0.0.0.0/0" "10.50.0.19"
assert_route "b-router-policy" "p2p-b-router-policy-b-router-upstream-selector--access-b-router-access-hostile--uplink-wan" "::/0" "fd42:dead:feed:1000:0:0:0:13"
assert_route "b-router-upstream-selector" "p2p-b-router-core-simulated-isp-b-router-upstream-selector" "0.0.0.0/0" "10.50.0.6"
assert_route "b-router-upstream-selector" "p2p-b-router-core-simulated-isp-b-router-upstream-selector" "::/0" "fd42:dead:feed:1000:0:0:0:6"

# Return routes to the hostile tenant must exist on both WAN and overlay cores,
# but public defaults must not leak onto hostile east-west lanes.
assert_route "b-router-core-simulated-isp" "p2p-b-router-core-simulated-isp-b-router-upstream-selector" "10.70.10.0/24" "10.50.0.7"
assert_route "b-router-core-simulated-isp" "p2p-b-router-core-simulated-isp-b-router-upstream-selector" "fd42:dead:feed:0070:0000:0000:0000:0000/64" "fd42:dead:feed:1000:0:0:0:7"
assert_route "b-router-core-nebula" "p2p-b-router-core-nebula-b-router-upstream-selector" "10.70.10.0/24" "10.50.0.5"
assert_route "b-router-core-nebula" "p2p-b-router-core-nebula-b-router-upstream-selector" "fd42:dead:feed:0070:0000:0000:0000:0000/64" "fd42:dead:feed:1000:0:0:0:5"
assert_route "b-router-policy" "p2p-b-router-downstream-selector-b-router-policy--access-b-router-access-hostile" "10.70.10.0/24" "10.50.0.10"
assert_route "b-router-policy" "p2p-b-router-downstream-selector-b-router-policy--access-b-router-access-hostile" "fd42:dead:feed:0070:0000:0000:0000:0000/64" "fd42:dead:feed:1000:0:0:0:a"
assert_route "b-router-downstream-selector" "p2p-b-router-access-hostile-b-router-downstream-selector" "10.70.10.0/24" "10.50.0.2"
assert_route "b-router-downstream-selector" "p2p-b-router-access-hostile-b-router-downstream-selector" "fd42:dead:feed:0070:0000:0000:0000:0000/64" "fd42:dead:feed:1000:0:0:0:2"

jq -r "${site_jq}
  | .nodes.\"b-router-core-nebula\".interfaces.\"overlay-east-west\" as \$iface
  | ((\$iface.routes.ipv4 // []) + (\$iface.routes.ipv6 // []))
  | map(\"\(.dst)|\(.overlay)|\(.peerSite // \"<none>\")|\(.proto)|\(.intent.kind)\")
  | sort
  | .[]" "${output_json}" >"${actual_overlay_routes}"

cat >"${expected_overlay_routes}" <<'EOF'
0.0.0.0/0|east-west|<none>|overlay|overlay-reachability
10.20.10.0/24|east-west|esp0xdeadbeef.site-a|overlay|overlay-reachability
10.20.15.0/24|east-west|esp0xdeadbeef.site-a|overlay|overlay-reachability
10.20.20.0/24|east-west|esp0xdeadbeef.site-a|overlay|overlay-reachability
10.20.30.0/24|east-west|esp0xdeadbeef.site-a|overlay|overlay-reachability
10.20.40.0/24|east-west|esp0xdeadbeef.site-a|overlay|overlay-reachability
::/0|east-west|<none>|overlay|overlay-reachability
fd42:dead:beef:10::/64|east-west|esp0xdeadbeef.site-a|overlay|overlay-reachability
fd42:dead:beef:15::/64|east-west|esp0xdeadbeef.site-a|overlay|overlay-reachability
fd42:dead:beef:20::/64|east-west|esp0xdeadbeef.site-a|overlay|overlay-reachability
fd42:dead:beef:30::/64|east-west|esp0xdeadbeef.site-a|overlay|overlay-reachability
fd42:dead:beef:40::/64|east-west|esp0xdeadbeef.site-a|overlay|overlay-reachability
EOF

if ! diff -u "${expected_overlay_routes}" "${actual_overlay_routes}" >&2; then
  fail "overlay-east-west routes or overlay reachability scope changed"
fi

jq -r "${site_jq}
  | [
      .nodes
      | to_entries[] as \$node
      | (\$node.value.interfaces // {})
      | to_entries[] as \$iface
      | ((\$iface.value.routes.ipv4 // []) + (\$iface.value.routes.ipv6 // []))[]
      | select(
          (.dst == \"0.0.0.0/0\" or .dst == \"::/0\")
          and .intent.kind == \"default-reachability\"
          and .lane.access == \"b-router-access-hostile\"
        )
      | \"\(\$node.key)|\(\$iface.key)|\(.dst)|\(.lane.uplink // \"<missing>\")|\(.metric // 0)|\(.via4 // .via6)\"
    ]
  | sort
  | .[]" "${output_json}" >"${actual_defaults}"

cat >"${expected_defaults}" <<'EOF'
b-router-downstream-selector|p2p-b-router-downstream-selector-b-router-policy--access-b-router-access-hostile|0.0.0.0/0|wan|0|10.50.0.11
b-router-downstream-selector|p2p-b-router-downstream-selector-b-router-policy--access-b-router-access-hostile|::/0|wan|0|fd42:dead:feed:1000:0:0:0:b
b-router-policy|p2p-b-router-policy-b-router-upstream-selector--access-b-router-access-hostile--uplink-wan|0.0.0.0/0|wan|1000|10.50.0.19
b-router-policy|p2p-b-router-policy-b-router-upstream-selector--access-b-router-access-hostile--uplink-wan|::/0|wan|1000|fd42:dead:feed:1000:0:0:0:13
b-router-upstream-selector|p2p-b-router-core-simulated-isp-b-router-upstream-selector|0.0.0.0/0|wan|1000|10.50.0.6
b-router-upstream-selector|p2p-b-router-core-simulated-isp-b-router-upstream-selector|::/0|wan|1000|fd42:dead:feed:1000:0:0:0:6
EOF

if ! diff -u "${expected_defaults}" "${actual_defaults}" >&2; then
  fail "hostile public defaults are over-permissive or choose an illogical lane"
fi

pass_timed "tri-site-hostile-forwarding-scope"
