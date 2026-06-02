#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: SMT-NFM-P2P-NEXTHOP-001
# GAMP-SCOPE: software-module-test

repo_root="$(git rev-parse --show-toplevel)"
source "${repo_root}/tests/lib/timing.sh"

archive_json="$(mktemp)"
output_json="$(mktemp)"
violations_json="$(mktemp)"
trap 'rm -f "${archive_json}" "${output_json}" "${violations_json}"' EXIT

nix flake archive --json "path:${repo_root}" >"${archive_json}"
labs_root="$(jq -er '.inputs["network-labs"].path' "${archive_json}")"
intent="${labs_root}/examples/tri-site-s-router-overlay-egress/intent.nix"

start_ms="$(test_now_ms)"
nix run "${repo_root}#compile-and-build-forwarding-model" -- "${intent}" >"${output_json}"
pass_timed "p2p-route-next-hop-peer-contract:compile" "${start_ms}"

jq '
  def strip_mask: split("/")[0];
  def peer_addrs($link; $node):
    ($link.endpoints // {})
    | to_entries
    | map(select(.key != $node) | .value)
    | {
        ipv4: (map(.addr4? // empty | strip_mask) | unique),
        ipv6: (map(.addr6? // empty | strip_mask) | unique)
      };

  [
    .enterprise
    | to_entries[] as $enterprise
    | $enterprise.value.site
    | to_entries[] as $site
    | ($site.value.links // {}) as $links
    | $site.value.nodes
    | to_entries[] as $node
    | ($node.value.interfaces // {})
    | to_entries[] as $iface
    | select(($iface.value.kind // null) == "p2p")
    | ($links[$iface.value.link // $iface.key] // null) as $link
    | select($link != null)
    | peer_addrs($link; $node.key) as $peers
    | (($iface.value.routes.ipv4 // [])[] | . as $route
      | select(($route.via4 // null) != null and (($peers.ipv4 | index($route.via4)) == null))
      | {
          enterprise: $enterprise.key,
          site: $site.key,
          node: $node.key,
          interface: $iface.key,
          family: 4,
          peerAddrs: $peers.ipv4,
          route: $route
        }),
      (($iface.value.routes.ipv6 // [])[] | . as $route
      | select(($route.via6 // null) != null and (($peers.ipv6 | index($route.via6)) == null))
      | {
          enterprise: $enterprise.key,
          site: $site.key,
          node: $node.key,
          interface: $iface.key,
          family: 6,
          peerAddrs: $peers.ipv6,
          route: $route
        })
  ]
' "${output_json}" >"${violations_json}"

if ! jq -e 'length == 0' "${violations_json}" >/dev/null; then
  echo "FAIL p2p-route-next-hop-peer-contract: p2p routes must use the peer endpoint of their own link" >&2
  jq . "${violations_json}" >&2
  exit 1
fi

pass_timed "p2p-route-next-hop-peer-contract"
