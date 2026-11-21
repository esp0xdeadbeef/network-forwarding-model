#!/usr/bin/env bash
# GAMP-ID: FS-315-HDS-010-SDS-010-SMS-010
# GAMP-SCOPE: software-module-test
set -euo pipefail

# Exit defaults must be derived symmetrically for both address families, on
# every node that carries one -- whatever kind of exit that node has.
#
# WHY (measured, not hypothetical). On 2026-11-21 a live cobalt router served
# IPv4 and dropped IPv6 for the same tenant on the same path. Nothing about a
# WAN uplink, a provider-overlay uplink, or a simulated ISP makes one family
# optional: the forwarding model derives a per-lane default per family, and a
# node that carries `0.0.0.0/0` on an interface without `::/0` on that same
# interface has dropped a family in derivation. Every hop downstream inherits
# the gap.
#
# WHAT THIS ASSERTS. Per node: the SET of interfaces carrying an IPv4 default
# must equal the set carrying an IPv6 default. Sets, not counts -- a default
# emitted for both families but on different interfaces is still an asymmetry
# and still wrong.
#
# The predicate names no core, no provider and no overlay. It runs over an
# ISP/PD fixture and a provider-overlay fixture and FAILS if either shape was
# not exercised, so a green run cannot come from testing only one.
#
# SCOPE NOTE. The NFM has no routing-table concept, so it cannot express the
# related defect found the same day: two interfaces allocating ONE policy table
# at ONE metric, where `ip route replace` makes them mutually exclusive and the
# surviving route depends on installation order. That belongs to the layer that
# allocates tables and is asserted at FS-381-HDS-010-SDS-010-SMS-020 in
# network-control-plane-model. This case deliberately does not fake it.

repo_root="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
source "${repo_root}/tests/lib/timing.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

fail_with() {
  printf 'FAIL %s: %s\n' "$1" "$2" >&2
  exit 1
}

fixtures=(
  "${repo_root}/tests/fixtures/examples/ipv6-pd-downstream-delegation/intent.nix"
  "${repo_root}/tests/fixtures/examples/tri-site-s-router-overlay-egress/intent.nix"
)

# Bump the compile timeout so a slow cold evaluation fails as a timeout, not as
# a wrong answer.
compile_fixture() {
  local intent="$1" out="$2" err="$3"
  if ! NETWORK_REPO_DIRECT_TEST_OK=1 \
    nix run "${repo_root}#compile-and-build-forwarding-model" -- "${intent}" >"${out}" 2>"${err}"; then
    printf 'STDERR (tail):\n' >&2
    tail -20 "${err}" >&2
    fail_with family-symmetry "compilation failed for $(basename "$(dirname "${intent}")")"
  fi
}

PROGRAM='
  def hasDef($r; $d): [ ($r // [])[]? | select((.dst // "") == $d) ] | length > 0;

  # Walk enterprise -> site -> node by their KEYS: a node object does not carry
  # its own name, and an interface object carries `node: null`, so the name is
  # only reachable as the key it is stored under.
  [ .enterprise | to_entries[] | (.value.site // {}) | to_entries[]
    | (.value.nodes // {}) | to_entries[]
    | .key as $node | (.value.interfaces // {}) as $ifs
    | { node: $node
      , v4: [ $ifs | to_entries[] | select(hasDef(.value.routes.ipv4; "0.0.0.0/0")) | .key ] | sort
      , v6: [ $ifs | to_entries[] | select(hasDef(.value.routes.ipv6; "::/0")) | .key ] | sort
      , plainExit4: [ $ifs | to_entries[]
                      | select(.value.overlay == null)
                      | select(hasDef(.value.routes.ipv4; "0.0.0.0/0")) ] | length
      , overlayExit6: [ $ifs | to_entries[]
                        | select(.value.overlay != null)
                        | select(hasDef(.value.routes.ipv6; "::/0")) ] | length
      } ]
'

saw_plain_exit=0
saw_overlay_exit=0
nodes_checked=0

for intent in "${fixtures[@]}"; do
  name="$(basename "$(dirname "${intent}")")"
  model="${tmpdir}/${name}.json"
  compile_fixture "${intent}" "${model}" "${tmpdir}/${name}.err"

  check="${tmpdir}/${name}.check.json"
  jq -r "${PROGRAM} | {
      asymmetric: [ .[] | select(.v4 != .v6) ],
      nodesWithExitDefault: ( map(select((.v4 | length) > 0 or (.v6 | length) > 0)) | length ),
      plainExit: any(.[]; .plainExit4 > 0),
      overlayExit: any(.[]; .overlayExit6 > 0)
    }" "${model}" >"${check}"

  asym="$(jq -r '.asymmetric | length' "${check}")"
  if [[ "${asym}" != "0" ]]; then
    echo "FAIL family-symmetry-exit-defaults [${name}]: a node derives an exit default for one family and not the other" >&2
    jq -r '.asymmetric[] | "  \(.node): v4 on [\(.v4 | join(", "))] but v6 on [\(.v6 | join(", "))]"' "${check}" >&2
    echo "  A WAN uplink, a provider-overlay uplink and a simulated ISP are equally required to carry both families." >&2
    exit 1
  fi

  checked="$(jq -r '.nodesWithExitDefault' "${check}")"
  if [[ "${checked}" == "0" ]]; then
    fail_with family-symmetry "[${name}] models no node carrying an exit default, so the clause is vacuous for this fixture"
  fi
  nodes_checked=$((nodes_checked + checked))

  [[ "$(jq -r '.plainExit' "${check}")" == "true" ]] && saw_plain_exit=$((saw_plain_exit + 1))
  [[ "$(jq -r '.overlayExit' "${check}")" == "true" ]] && saw_overlay_exit=$((saw_overlay_exit + 1))

  echo "  ok ${name}: ${checked} node(s) with exit defaults, symmetric across families"
done

# The predicate must have been exercised on both kinds of exit. Without these,
# a green run says nothing about the shape it never saw -- which is how a
# family-specific derivation gap could ship.
if [[ "${saw_plain_exit}" == "0" ]]; then
  fail_with family-symmetry "no fixture exercised a non-overlay (ISP/WAN) exit, so that shape is unproven"
fi
if [[ "${saw_overlay_exit}" == "0" ]]; then
  fail_with family-symmetry "no fixture exercised an overlay (provider) exit, so that shape is unproven"
fi

echo "PASS family-symmetry-exit-defaults (${nodes_checked} node(s) across ${#fixtures[@]} fixtures; ISP and provider-overlay exits both exercised)"
