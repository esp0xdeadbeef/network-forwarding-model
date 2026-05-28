#!/usr/bin/env bash
# GAMP-ID: SMT-NFM-OVERLAY-UNDERLAY-CONTRACT-001
# GAMP-SCOPE: software-module-test
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
source "${repo_root}/tests/lib/timing.sh"

labs_path="$(
  nix flake archive --json "path:${repo_root}" \
    | jq -er '.inputs["network-labs"].path'
)"
model_json="$(mktemp)"
trap 'rm -f "${model_json}"' EXIT

nix run "${repo_root}#compile-and-build-forwarding-model" -- \
  "${labs_path}/examples/s-router-overlay-dns-lane-policy/intent.nix" \
  >"${model_json}"

if jq -e '
  .enterprise.esp0xdeadbeef.site["site-a"] as $site
  | ($site.overlayReachability["east-west"].underlayAccess // {}) as $underlay
  | $underlay.kind == "tenant"
    and $underlay.name == "client"
    and ($site.links
      | to_entries
      | any(
          (.value.overlay // null) == "east-west"
          and (.value.laneMeta.kind // null) == "access-uplink"
          and (.value.laneMeta.access // null) == "s-router-access-client"
        ))
' "${model_json}" >/dev/null; then
  pass_timed "transport-overlay-underlay-access-contract"
else
  cat >&2 <<'EOF'
FAIL transport-overlay-underlay-access-contract

transport.overlays[].underlayAccess is intent-owned forwarding data. NFM must
preserve the selected underlay access in overlayReachability and keep the
matching access-uplink lane available so CPM can source-scope runtime-origin
overlay bootstrap traffic without guessing from names or route destinations.
EOF
  jq '.enterprise.esp0xdeadbeef.site["site-a"].overlayReachability["east-west"]' "${model_json}" >&2
  exit 1
fi
