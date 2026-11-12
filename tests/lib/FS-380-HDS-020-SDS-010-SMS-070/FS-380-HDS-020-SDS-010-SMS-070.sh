#!/usr/bin/env bash
# GAMP-ID: FS-380-HDS-020-SDS-010-SMS-070
# GAMP-SCOPE: software-module-test
#
# SPEC:   GAMP/SMS/FS-380-HDS-020-SDS-010-SMS-070.md
# OWNER:  network-forwarding-model
#
# Predicates: a declarative egress path preference selects the active path
# deterministically when a scope has several valid selected exits, and the
# preference is declared in NFM rather than invented downstream.
#
# Behavioural: calls the real candidate selector with a minimal topology fixture and
# asserts the returned candidate set for a declared preference, an absent
# preference, and a preference naming an uplink the topology does not carry.
#
# Not executed before commit.
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"

fail() { echo "FAIL egress-path-preference: $*" >&2; exit 1; }

mod="implementation/lib/routing/internal-routes/route-candidates.nix"
[[ -f "${repo_root}/${mod}" ]] || fail "P1 the candidate selector does not exist at ${mod}"

pick() {
  nix eval --no-write-lock-file --impure --json --expr '
    let
      f = builtins.getFlake ("path:'"${repo_root}"'");
      pkgs = import f.inputs.nixpkgs { };
      lib = pkgs.lib;
      # These mirror route-context.nix, where both take a LINK (an attrset) and
      # read `link.laneMeta.{access,uplink}` -- not a link name:
      #   laneUplinkNameFromLink = link: (laneMetaForLink link).uplink or null;
      #   laneAccessNodeNameFromLink = link: (laneMetaForLink link).access or null;
      # The fixture compared plain strings instead, so every lookup returned the
      # null branch and a declared "wan" preference selected [] -- which read as
      # a selector defect.
      routeContext = {
        laneAccessNodeNameFromLink = link: link.laneMeta.access or null;
        laneUplinkNameFromLink = link: link.laneMeta.uplink or null;
      };
      topo = {
        links = {
          l-wan.laneMeta = { access = "access1"; uplink = "wan"; };
          l-vpn.laneMeta = { access = "access1"; uplink = "vpn"; };
        };
      };
      call = preferredUplinks:
        import ("'"${repo_root}/${mod}"'") {
          inherit lib routeContext topo preferredUplinks;
          baseLinkName = null;
          hopNode = "core1";
          isOverlay = false;
          link = { membersOf = _: [ "access1" "core1" ]; };
          nodeName = "access1";
          routeGraph = null;
        };
    in
      { declared = call '"$1"'; none = call [ ]; }
  '
}

# SN1: a declared preference selects its own lane and not the other one.
out="$(pick '[ "wan" ]')" || fail "P1 the selector could not be evaluated:
${out}"
declared="$(jq -c '.declared' <<<"${out}")"
[[ "${declared}" == '["l-wan"]' ]] \
  || fail "SN1 a declared preference for the wan uplink selected ${declared} rather than only l-wan"

# SN2: the other uplink selects the other lane, so the preference is what decides.
out="$(pick '[ "vpn" ]')" || fail "P1 the selector failed for the vpn preference"
declared="$(jq -c '.declared' <<<"${out}")"
[[ "${declared}" == '["l-vpn"]' ]] \
  || fail "SN2 a declared preference for the vpn uplink selected ${declared} rather than only l-vpn"

# P2: with no preference declared the selector must not invent one. The unfiltered
# candidate set is returned instead, so the absence of a preference is visible.
out="$(pick '[ "wan" ]')" || fail "P1 the selector failed"
none="$(jq -c '.none' <<<"${out}")"
[[ "${none}" == '[]' ]] \
  || fail "P2 an empty preference returned ${none}; the selector invented a preferred lane where none was declared"

# SN3: a preference naming an uplink the topology does not carry must select
# nothing, rather than falling back to an arbitrary lane.
out="$(pick '[ "uplink-not-modelled" ]')" || fail "P1 the selector failed for an unmodelled preference"
declared="$(jq -c '.declared' <<<"${out}")"
[[ "${declared}" == '[]' ]] \
  || fail "SN3 a preference naming an unmodelled uplink selected ${declared} instead of nothing"

echo "PASS egress-path-preference"
