#!/usr/bin/env bash
# GAMP-ID: FS-260-HDS-010-SDS-010-SMS-050
# GAMP-SCOPE: software-module-test
#
# ============================================================================
# WHY THIS TEST IS NOT NEGOTIABLE
# ============================================================================
#
# A point-to-point lane (/31 for IPv4, /127 for IPv6) is DIRECTLY CONNECTED
# state. The /31 contains exactly two addresses; one on each end of one wire.
# Both endpoints belong to the lane. A node that holds NEITHER address is not on
# that wire and can never reach it through a next hop, because there is no
# interface on which such a packet could make progress.
#
# The NFM used to attach every lane in the site to every node, each carrying
# `via4` = that node's OWN peer address. On the cobalt model that is 634 foreign
# lane routes. The rendered consequence, measured on the DS:
#
#   ds$ ip route get 10.1.0.16 from 10.1.0.0 iif pacds
#   10.1.0.16 from 10.1.0.0 via 10.1.0.0 dev pacds table 1001
#
# 10.1.0.16 is on the core<->upstream-selector lane. pacds holds neither address
# of that /31. The route says "the next hop IS my own peer", so the packet leaves
# pacds and arrives at the node on the other end of pacds -- the policy point --
# which holds the same broken route and sends it straight back.
#
# This must be fixed rather than tolerated:
#
#   1. It cannot be corrected downstream. The CPM copies NFM routes through and a
#      renderer may not discard forwarding intent it was handed; doing so is
#      repair-by-guessing. Measured: a renderer-side filter was added, went live,
#      and changed nothing, because the routes arrive with table and gateway
#      already assigned.
#
#   2. It is silent. Every unit reports healthy and no diagnostic is emitted. The
#      site renders, boots and answers pings. The only symptom is that name
#      resolution fails while `ping 1.1.1.1` and HTTPS succeed, which reads like a
#      DNS bug and is not one.
#
#   3. It is not a suboptimal route, it is an invalid one. `via4` equals the peer
#      of the link the route is installed on, so the next hop is whatever node is
#      at the other end of THAT link, regardless of where the destination is.
#
#   4. It grows with the site. Every node and every point-to-point link adds a
#      route to every node, so the defect scales quadratically.
#
# Spec basis, FS-260-HDS-010-SDS-010-SMS-050 ("Module Failure Conditions"):
#
#   - "The NFM emits a route, link, or forwarding relationship without explicit
#      forwarding intent authority from the compiler's canonical staged model."
#      The compiler emits none of these prefixes; verified by grepping compiled
#      output for 10.1.0.16/31 (0 occurrences). The NFM emitted 30.
#   - "The NFM invents topology, interface names, or addressing from local
#      defaults instead of explicit model data." A lane address is explicit model
#      data; attaching it to a node that holds neither of its addresses invents
#      the adjacency.
#
# ============================================================================
# WHERE THE FIX LIVES
# ============================================================================
#
# Emitter: implementation/lib/routing/internal-routes/route-groups.nix
#     routeIntent = { kind = intentKind; }
#       // lib.optionalAttrs ((sample.owner or null) != null) { accessNode = sample.owner; }
#   emitted `internal-reachability` with `accessNode` naming a DIFFERENT node than
#   the one the route was installed on.
#
# Annotations: implementation/lib/routing/internal-routes/remote-prefixes/
#   route-entries.nix annotates each p2p entry with `laneLinkName` and
#   `laneLinkMembers`; lane-ownership.nix states the membership rule once for
#   every consumer.
#
# ============================================================================
# THE INVARIANT THIS CASE ASSERTS
# ============================================================================
#
# For every node, interface and route: if the destination is a lane address, this
# node must hold one of the two addresses of that lane. Holding either end is
# legitimate and is exactly what connected-reachability emits. Holding neither is
# the defect.
#
# The two halves are asserted separately so a regression cannot hide behind a
# passing total:
#
#   OWNERSHIP   no route may target a lane this node holds no address on.
#   NEXT HOP    a lane route on a node that IS an endpoint must not carry a
#               gateway. The lane is directly connected; a gateway on it means
#               the packet is sent to a third party to reach its own wire.
#
# Any node holding either address of a /31 is an endpoint by construction, so the
# rule needs no separate link lookup and cannot drift from link metadata.
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

fail() {
  printf 'FAIL fabric-lane-next-hop-ownership: %s\n' "$*" >&2
  exit 1
}

system="${NIX_SYSTEM:-$(nix eval --impure --raw --expr 'builtins.currentSystem')}"

for example_dir in "${repo_root}"/tests/fixtures/examples/*/; do
  example="$(basename "${example_dir}")"
  [[ -f "${example_dir}intent.nix" ]] || continue

  report="${tmp_dir}/${example}.json"
  if ! NFM_REPO="${repo_root}" NFM_SYSTEM="${system}" NFM_EXAMPLE="${example}" \
    nix eval --impure --json --file "${repo_root}/tests/lib/FS-260-HDS-010-SDS-010-SMS-050/lane-ownership-report.nix" \
      >"${report}" 2>"${tmp_dir}/${example}.err"; then
    fail "example ${example} did not evaluate:
$(cat "${tmp_dir}/${example}.err")"
  fi

  count="$(jq -r '.violationCount' "${report}")"
  if [[ "${count}" != "0" ]]; then
    {
      printf 'FAIL fabric-lane-next-hop-ownership: %s has %s lane-route violations.\n\n' "${example}" "${count}"
      printf 'A /31 or /127 is directly connected state. Its two addresses live on one wire,\n'
      printf 'and only the nodes holding those addresses are on it. A lane route anywhere else\n'
      printf 'is installed with that node'"'"'s own peer as next hop, so the packet leaves and\n'
      printf 'comes straight back:\n\n'
      printf '  ds$ ip route get 10.1.0.16 from 10.1.0.0 iif pacds\n'
      printf '  10.1.0.16 from 10.1.0.0 via 10.1.0.0 dev pacds table 1001\n\n'
      printf 'Effect: a lane beyond the policy point reads as reachable through the access node.\n'
      printf 'Name resolution is what breaks, while ping and HTTPS still work, so the site looks\n'
      printf 'healthy while it cannot resolve a name.\n\n'
      printf 'Emitter to fix (not downstream):\n'
      printf '  implementation/lib/routing/internal-routes/route-groups.nix\n'
      printf '    routeIntent = { kind = intentKind; } // lib.optionalAttrs ((sample.owner or null) != null) { accessNode = sample.owner; }\n'
      printf '  implementation/lib/routing/internal-routes/remote-prefixes/route-entries.nix\n'
      printf '    annotates each p2p entry with laneLinkName / laneLinkMembers; lane-ownership.nix states the rule.\n\n'
      printf 'First %s of %s (kind, node, interface, prefix, next hop, real endpoints):\n' "$(jq -r '.violations | length' "${report}")" "${count}"
      jq -r '.violations[] | "  [\(.kindOf)] \(.thisNode) if=\(.ifName) dst=\(.dst) via4=\(.via4 // "null") endpoints=\(.realEndpoints | join(",")) intent=\(.intentKind) accessNode=\(.intentAccessNode)"' "${report}"
    } >&2
    exit 1
  fi

  printf 'PASS fabric-lane-next-hop-ownership: %s — every lane route is on an endpoint, without a gateway\n' "${example}"
done
