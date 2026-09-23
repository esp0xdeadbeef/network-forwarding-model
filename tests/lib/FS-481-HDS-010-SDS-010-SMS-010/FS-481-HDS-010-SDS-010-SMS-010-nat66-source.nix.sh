#!/usr/bin/env bash
set -euo pipefail

# GAMP-ID: FS-481-HDS-010-SDS-010-SMS-010
# GAMP-SCOPE: software-module-test
#
# FS-322/FS-481: an access declares its exits with `selects`; the tenant
# attached to that access egresses through every selected uplink. A NAT66 exit
# must therefore name that tenant as a source prefix even when no relation
# pins the exit. multi-client is attached to access-multi, which selects all
# three members, so its prefix must appear on every member; ordered-client is
# attached to access-ordered, which selects only isp-v6, so it must appear only
# there.

ROOT="${NETWORK_FORWARDING_MODEL_ROOT:-${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}}"
LABS="${NETWORK_LABS_PATH:-/home/deadbeef/github/network-labs}"
TRACE="FS-481-HDS-010-SDS-010-SMS-010"

result="$(nix eval --impure --json --expr "
  let
    nfm = builtins.getFlake (toString ${ROOT});
    source = import ${LABS}/GAMP/SMT/${TRACE}/intent.nix;
    base = source.mini-smt.smt-shape;
    nat66Uplink = {
      ipv4 = [ \"0.0.0.0/0\" ];
      ipv6 = [ \"::/0\" ];
      egress.ipv6.translation.mode = \"nat66\";
    };
    seeded = base // {
      topology = base.topology // {
        nodes = base.topology.nodes // {
          core-dual = base.topology.nodes.core-dual // { uplinks.isp-dual = nat66Uplink; };
          core-v4 = base.topology.nodes.core-v4 // { uplinks.isp-v4 = nat66Uplink; };
          core-v6 = base.topology.nodes.core-v6 // { uplinks.isp-v6 = nat66Uplink; };
        };
      };
    };
    compiled = nfm.inputs.network-compiler.lib.compile builtins.currentSystem {
      mini-smt = { smt-shape = seeded; };
    };
    forwarding = nfm.libBySystem.\${builtins.currentSystem}.model compiled;
    nodes = forwarding.enterprise.mini-smt.site.smt-shape.nodes;
  in {
    dual = nodes.core-dual.egressIntent.nat66.isp-dual.sourcePrefixes;
    v4 = nodes.core-v4.egressIntent.nat66.isp-v4.sourcePrefixes;
    v6 = nodes.core-v6.egressIntent.nat66.isp-v6.sourcePrefixes;
  }
")"

# multi-client (fd42:481:20::/64) egresses through every selected member.
jq -e '
  ([.dual, .v4, .v6] | map(index("fd42:481:20::/64") != null) | all)
' <<<"$result" >/dev/null || {
  echo "FAIL ${TRACE}: a selected NAT66 uplink is missing the access tenant source prefix" >&2
  jq '.' <<<"$result" >&2
  exit 1
}

# ordered-client (fd42:481:21::/64) selects only isp-v6.
jq -e '
  (.v6 | index("fd42:481:21::/64") != null)
  and (.dual | index("fd42:481:21::/64") == null)
  and (.v4 | index("fd42:481:21::/64") == null)
' <<<"$result" >/dev/null || {
  echo "FAIL ${TRACE}: a tenant leaked onto an uplink its access did not select" >&2
  jq '.' <<<"$result" >&2
  exit 1
}

echo "PASS ${TRACE}: NAT66 egress derives tenant source prefixes from the access exit selection"
