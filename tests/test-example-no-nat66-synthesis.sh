#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)"
source "${repo_root}/tests/lib/timing.sh"

output_json="$(mktemp)"
checks_json="$(mktemp)"
trap 'rm -f "${output_json}" "${checks_json}"' EXIT

start_ms="$(test_now_ms)"
labs_path="${NETWORK_LABS_PATH:-/home/deadbeef/github/network-labs}"
nix run "${repo_root}#compile-and-build-forwarding-model" -- \
  "${labs_path}/examples/s-router-overlay-dns-lane-policy/intent.nix" \
  | jq -c '.enterprise' >"${output_json}"
pass_timed "example-no-nat66-synthesis:compile" "${start_ms}"

OUTPUT_JSON="${output_json}" nix eval --impure --json --expr '
  let
    enterprise = builtins.fromJSON (builtins.readFile (builtins.getEnv "OUTPUT_JSON"));
    sites =
      builtins.concatMap
        (enterpriseName:
          let enterpriseData = enterprise.${enterpriseName};
          in builtins.map (siteName: enterpriseData.site.${siteName}) (builtins.attrNames enterpriseData.site))
        (builtins.attrNames enterprise);
    nat66Entries =
      builtins.concatMap
        (site:
          builtins.concatMap
            (nodeName:
              let nat66 = site.nodes.${nodeName}.egressIntent.nat66 or {};
              in builtins.map (uplink: nat66.${uplink}) (builtins.attrNames nat66))
            (builtins.attrNames site.nodes))
        sites;
  in {
    examplesDoNotSynthesizeNat66 = nat66Entries == [];
  }
' > "${checks_json}"

failed_checks="$(jq -r 'to_entries[] | select(.value != true) | .key' "${checks_json}")"
if [[ -n "${failed_checks}" ]]; then
  echo "FAIL example-no-nat66-synthesis" >&2
  echo "failed checks:" >&2
  while IFS= read -r failed_check; do
    echo "  ${failed_check}" >&2
  done <<< "${failed_checks}"
  gron "${output_json}" | rg 'egressIntent.nat66|router-core|simulated' >&2 || true
  exit 1
fi

echo "PASS example-no-nat66-synthesis"
