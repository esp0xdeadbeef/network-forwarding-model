#!/usr/bin/env bash
# GAMP-ID: FS-380-HDS-020-SDS-010-SMS-070
# GAMP-SCOPE: software-module-test
#
# SPEC:   GAMP/SMS/FS-380-HDS-020-SDS-010-SMS-070.md
# OWNER:  network-forwarding-model
#
# Predicates: a declarative egress path preference model exists so that when a
# tenant scope has multiple valid selected exits the active path is chosen
# deterministically rather than derived from routing algorithm behaviour, and the
# preference is declared in NFM rather than invented by CPM or a renderer.
#
# Contract check, not behavioural. The candidate selector needs a full topology
# and route context to run, so this case asserts the mechanism's exposed shape
# instead: that the preference is an accepted input defaulting to empty, that it is
# normalised rather than dropped, that an empty preference falls back to the full
# candidate set, that candidates are filtered by the declared uplink, and that the
# overlay/non-overlay split is preserved. A behavioural version needs a topology
# fixture and is the next step for this atom.
#
# The SMS points at the existing `preferredUplinks` mechanism, which lives under
# implementation/lib/routing/, not lib/.
#
# Not executed before commit.
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/direct-test-guard.sh"

fail() { echo "FAIL egress-path-preference: $*" >&2; exit 1; }

ctx="${repo_root}/implementation/lib/routing/route-context.nix"
cand="${repo_root}/implementation/lib/routing/internal-routes/route-candidates.nix"

[[ -f "${ctx}" ]] || fail "P1 the route-context module does not exist at ${ctx#"${repo_root}/"}"
[[ -f "${cand}" ]] || fail "P1 the route-candidate module does not exist at ${cand#"${repo_root}/"}"

# P1: the preference must be an accepted input of the routing context, defaulted
# to empty so an absent preference is not an error.
if ! grep -qE 'preferredUplinks\s*\?\s*\[\s*\]' "${ctx}"; then
  fail "P1 preferredUplinks is not an accepted input defaulting to an empty list, so a model without a preference would fail rather than fall back"
fi

# P1: the preference must survive normalisation rather than being dropped. The
# context de-duplicates and stringifies it; assert that step exists so a caller
# cannot pass a value that silently disappears.
if ! grep -qE 'preferredUplinkSet' "${ctx}"; then
  fail "P1 the context does not normalise preferredUplinks into a set, so the declared order may not reach the selector"
fi

# P2: with no preference the selector must fall back to all candidates rather
# than to none, otherwise an unpreferenced model would lose its paths.
if ! grep -qE 'preferredUplinks\s*==\s*\[\s*\]' "${cand}"; then
  fail "P2 the selector has no empty-preference branch, so a model that declares no preference cannot fall back to its full candidate set"
fi

# P2: the preference must filter candidates by uplink name, not reorder them by
# an algorithm, so the chosen path is deterministic and declared.
if ! grep -qE 'builtins\.elem uplinkName preferredUplinks' "${cand}"; then
  fail "P2 the selector does not filter candidates by the declared uplink preference, so the active path is not chosen from the declaration"
fi

# P2: the overlay/non-overlay split must be preserved, so a preference does not
# silently promote an overlay lane into a non-overlay path.
if ! grep -qE 'nonOverlayPreferredCandidates' "${cand}"; then
  fail "P2 the selector does not keep a non-overlay view of the preferred candidates, so a preference could promote an overlay lane into a non-overlay path"
fi

echo "PASS egress-path-preference"
