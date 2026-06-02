#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: SMT-NFM-FS460-OVERLAY-PEERSITE-IDENTITY-001
# GAMP-SCOPE: software-module-test

repo_root="$(git rev-parse --show-toplevel)"
source "${repo_root}/tests/lib/timing.sh"

archive_json="$(mktemp)"
trap 'rm -f "${archive_json}" "${output_jsons[@]:-}"' EXIT

nix flake archive --json "path:${repo_root}" >"${archive_json}"
labs_root="$(jq -er '.inputs["network-labs"].path' "${archive_json}")"
examples=(
  s-router-overlay-dns-lane-policy
  tri-site-s-router-overlay-egress
)
output_jsons=()

for example in "${examples[@]}"; do
  output_json="$(mktemp)"
  output_jsons+=("${output_json}")
  intent="${labs_root}/examples/${example}/intent.nix"

  start_ms="$(test_now_ms)"
  nix run "${repo_root}#compile-and-build-forwarding-model" -- "${intent}" >"${output_json}"
  pass_timed "overlay-interface-no-peer-null-duplicates:${example}:compile" "${start_ms}"

  jq -e '
    [
      .enterprise[]?.site[]?.nodes[]?.interfaces[]?
      | select((.kind // null) == "overlay")
      | [
          (.routes.ipv4[]? | . + { family: 4 }),
          (.routes.ipv6[]? | . + { family: 6 })
        ] as $overlayRoutes
      | $overlayRoutes[]
      | select((.peerSite // null) == null)
      | . as $nullPeer
      | select(
          any($overlayRoutes[];
            .family == $nullPeer.family
            and .dst == $nullPeer.dst
            and (.overlay // null) == ($nullPeer.overlay // null)
            and (.peerSite // null) != null)
        )
    ] | length == 0
  ' "${output_json}" >/dev/null || {
    echo "FAIL overlay-interface-no-peer-null-duplicates: ${example}: peerSite-null overlay routes duplicate concrete peerSite routes" >&2
    jq '
      .enterprise[]?.site[]?.nodes
      | to_entries[] as $node
      | ($node.value.interfaces // {})
      | to_entries[] as $iface
      | select(($iface.value.kind // null) == "overlay")
      | { node: $node.key, interface: $iface.key, routes: $iface.value.routes }
    ' "${output_json}" >&2
    exit 1
  }

  jq -e '
    [
      .enterprise[]?.site[]?.nodes[]?.interfaces[]?
      | select((.kind // null) == "overlay")
      | ((.routes.ipv4 // []) + (.routes.ipv6 // []))[]
      | select(
          (.proto // null) == "overlay"
          and ((.dst // null) == "0.0.0.0/0" or (.dst // null) == "::/0")
        )
    ] | length == 0
  ' "${output_json}" >/dev/null || {
    echo "FAIL overlay-interface-no-peer-null-duplicates: ${example}: overlay interfaces must not advertise default routes as overlay reachability" >&2
    jq '
      .enterprise[]?.site[]?.nodes
      | to_entries[] as $node
      | ($node.value.interfaces // {})
      | to_entries[] as $iface
      | select(($iface.value.kind // null) == "overlay")
      | ((($iface.value.routes.ipv4 // []) + ($iface.value.routes.ipv6 // []))[]
        | select((.proto // null) == "overlay" and ((.dst // null) == "0.0.0.0/0" or (.dst // null) == "::/0"))
        | { node: $node.key, interface: $iface.key, route: . })
    ' "${output_json}" >&2
    exit 1
  }

  jq -e '
    [
      .enterprise[]?.site[]?.nodes
      | to_entries[] as $node
      | ($node.value.interfaces // {})
      | to_entries[] as $iface
      | select(($iface.value.kind // null) == "overlay")
      | ((($iface.value.routes.ipv4 // []) + ($iface.value.routes.ipv6 // []))[]
        | select((.proto // null) == "overlay")
        | select((.overlay // null) == null or (.peerSite // null) == null)
        | { node: $node.key, interface: $iface.key, route: . })
    ] | length == 0
  ' "${output_json}" >/dev/null || {
    echo "FAIL overlay-interface-no-peer-null-duplicates: ${example}: overlay proto routes must carry overlay and peerSite metadata" >&2
    jq '
      .enterprise[]?.site[]?.nodes
      | to_entries[] as $node
      | ($node.value.interfaces // {})
      | to_entries[] as $iface
      | select(($iface.value.kind // null) == "overlay")
      | ((($iface.value.routes.ipv4 // []) + ($iface.value.routes.ipv6 // []))[]
        | select((.proto // null) == "overlay")
        | select((.overlay // null) == null or (.peerSite // null) == null)
        | { node: $node.key, interface: $iface.key, route: . })
    ' "${output_json}" >&2
    exit 1
  }

  jq -e '
    [
      .enterprise[]?.site[]?.nodes
      | to_entries[] as $node
      | ($node.value.interfaces // {})
      | to_entries[] as $iface
      | select(($iface.value.kind // null) == "overlay")
      | ((($iface.value.routes.ipv4 // []) + ($iface.value.routes.ipv6 // []))[]
        | select(
            (.intent.kind // null) == "overlay-reachability"
            and ((.overlay // null) == null or (.peerSite // null) == null)
          )
        | { node: $node.key, interface: $iface.key, route: . })
    ] | length == 0
  ' "${output_json}" >/dev/null || {
    echo "FAIL overlay-interface-no-peer-null-duplicates: ${example}: overlay reachability routes must carry overlay and peerSite metadata" >&2
    jq '
      .enterprise[]?.site[]?.nodes
      | to_entries[] as $node
      | ($node.value.interfaces // {})
      | to_entries[] as $iface
      | select(($iface.value.kind // null) == "overlay")
      | ((($iface.value.routes.ipv4 // []) + ($iface.value.routes.ipv6 // []))[]
        | select(
            (.intent.kind // null) == "overlay-reachability"
            and ((.overlay // null) == null or (.peerSite // null) == null)
          )
        | { node: $node.key, interface: $iface.key, route: . })
    ' "${output_json}" >&2
    exit 1
  }

  jq -e '
    [
      .enterprise[]?.site[]?.nodes
      | to_entries[] as $node
      | ($node.value.interfaces // {})
      | to_entries[] as $iface
      | ((($iface.value.routes.ipv4 // []) + ($iface.value.routes.ipv6 // []))[]
        | select(
            (.intent.kind // null) == "overlay-reachability"
            and ((.overlay // null) == null or (.peerSite // null) == null)
          )
        | { node: $node.key, interface: $iface.key, route: . })
    ] | length == 0
  ' "${output_json}" >/dev/null || {
    echo "FAIL overlay-interface-no-peer-null-duplicates: ${example}: every overlay-reachability route must carry overlay and peerSite metadata" >&2
    jq '
      .enterprise[]?.site[]?.nodes
      | to_entries[] as $node
      | ($node.value.interfaces // {})
      | to_entries[] as $iface
      | ((($iface.value.routes.ipv4 // []) + ($iface.value.routes.ipv6 // []))[]
        | select(
            (.intent.kind // null) == "overlay-reachability"
            and ((.overlay // null) == null or (.peerSite // null) == null)
          )
        | { node: $node.key, interface: $iface.key, route: . })
    ' "${output_json}" >&2
    exit 1
  }
done

pass_timed "overlay-interface-no-peer-null-duplicates"
