#!/usr/bin/env bash
# GAMP-ID: FS-260-HDS-010-SDS-010-SMS-050
# GAMP-SCOPE: software-module-test
#
# The forwarding model derives the DNS resolver path from the DNS relationship
# endpoints and the canonical staged topology. access<->access MUST cross the
# policy point. A supplied resolverPath is rejected by the compiler input gate
# (network-compiler), so the forwarding model never receives one.
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"

out="$(nix eval --impure --json --expr "
let
  lib = (import <nixpkgs> {}).lib;
  mod = import ${repo_root}/implementation/lib/routing/site-resolver-paths.nix { inherit lib; };
  site = {
    nodes = {
      access-vlan3 = { role = \"access\"; attachments = [ { kind = \"tenant\"; name = \"vlan3\"; } ]; };
      access-vlan2 = { role = \"access\"; attachments = [ { kind = \"tenant\"; name = \"vlan2\"; } ]; };
      ds = { role = \"downstream-selector\"; };
      pol = { role = \"policy\"; };
      us = { role = \"upstream-selector\"; };
      cor = { role = \"core\"; attachments = [ { kind = \"tenant\"; name = \"cor\"; } ]; };
    };
    ownership = { endpoints = [
      { kind = \"host\"; name = \"vlan3-dns\"; tenant = \"vlan3\"; }
      { kind = \"host\"; name = \"vlan2-dns\"; tenant = \"vlan2\"; }
      { kind = \"host\"; name = \"core-dns\"; tenant = \"cor\"; }
    ]; };
    dns = { localSharingRelations = [
      { namespace = \"lan.\"; authority = { service = \"vlan2-dns\"; }; requester = { service = \"vlan3-dns\"; }; }
      { namespace = \"wan.\"; authority = { service = \"core-dns\"; }; requester = { service = \"vlan3-dns\"; }; }
    ]; };
  };
in mod.resolverPaths site
")"

# access<->access must cross the policy point.
aa="$(jq -c '.[] | select(.namespace == "lan.") | .pathStages' <<<"$out")"
if [[ "$aa" != '["access","downstream-selector","policy","downstream-selector","access"]' ]]; then
  echo "FAIL resolver-path-derivation: access<->access path is not canonical: $aa" >&2
  exit 1
fi

# The policy point must be present and named.
pol="$(jq -r '.[] | select(.namespace == "lan.") | .policyPoint' <<<"$out")"
if [[ "$pol" != "pol" ]]; then
  echo "FAIL resolver-path-derivation: policy point missing: '$pol'" >&2
  exit 1
fi

# Path nodes include the policy point between the two access nodes.
pn="$(jq -c '.[] | select(.namespace == "lan.") | .pathNodes' <<<"$out")"
if [[ "$pn" != '["access-vlan3","ds","pol","ds","access-vlan2"]' ]]; then
  echo "FAIL resolver-path-derivation: unexpected pathNodes: $pn" >&2
  exit 1
fi

# access->core crosses policy and upstream-selector.
ac="$(jq -c '.[] | select(.namespace == "wan.") | .pathStages' <<<"$out")"
if [[ "$ac" != '["access","downstream-selector","policy","upstream-selector","core"]' ]]; then
  echo "FAIL resolver-path-derivation: access->core path is not canonical: $ac" >&2
  exit 1
fi

echo "PASS resolver-path-derivation"
