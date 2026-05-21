#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)"
source "${repo_root}/tests/lib/timing.sh"

output_json="$(mktemp)"
checks_json="$(mktemp)"
trap 'rm -f "${output_json}" "${checks_json}"' EXIT

start_ms="$(test_now_ms)"
REPO_ROOT="${repo_root}" \
LAB_INPUT="/home/deadbeef/github/network-labs/labs/lab-s-sigma/s-router-test-three-site" \
nix eval --extra-experimental-features 'nix-command flakes' --impure --json --expr '
  let
    nfm = builtins.getFlake ("path:" + builtins.getEnv "REPO_ROOT");
    out = nfm.libBySystem.x86_64-linux.buildFromCompilerInputPath (
      builtins.getEnv "LAB_INPUT" + "/getCompilerInput.nix"
    );
  in out.enterprise.esp.site
' > "${output_json}"
pass_timed "sigma-simulated-isp-nat66-contract:compile" "${start_ms}"

OUTPUT_JSON="${output_json}" nix eval --impure --json --expr '
  let
    site = builtins.fromJSON (builtins.readFile (builtins.getEnv "OUTPUT_JSON"));
    hasAll = expected: actual: builtins.all (value: builtins.elem value actual) expected;
    warningMentionsNat66 = intent:
      builtins.match ".*NAT66.*" (intent.warning or "") != null;
    nixosIspA = site.nixos.nodes."nixos-router-core-isp-a".egressIntent.nat66."isp-a";
    nixosIspB = site.nixos.nodes."nixos-router-core-isp-b".egressIntent.nat66."isp-b";
    clabIsp = site.clab.nodes."clab-router-core-simulated-isp".egressIntent.nat66.wan;
    hetzCore = site.hetz.nodes."hetz-router-core".egressIntent.nat66 or {};
    normalNixosPrefixes = [
      "fd42:dead:beef:10::/64"
      "fd42:dead:beef:15::/64"
      "fd42:dead:beef:20::/64"
      "fd42:dead:beef:50::/64"
    ];
    normalClabPrefixes = [
      "fd42:dead:feed:15::/64"
      "fd42:dead:feed:20::/64"
      "fd42:dead:feed:50::/64"
    ];
  in {
    nixosIspAModeled = nixosIspA.mode == "nat66";
    nixosIspBModeled = nixosIspB.mode == "nat66";
    nixosIspAWarns = warningMentionsNat66 nixosIspA;
    nixosIspBWarns = warningMentionsNat66 nixosIspB;
    nixosIspASourceScope = hasAll normalNixosPrefixes nixosIspA.sourcePrefixes;
    nixosIspBSourceScope = hasAll normalNixosPrefixes nixosIspB.sourcePrefixes;
    nixosIspAExcludesHostileUla = !(builtins.elem "fd42:dead:beef:70::/64" nixosIspA.sourcePrefixes);
    nixosIspBExcludesHostileUla = !(builtins.elem "fd42:dead:beef:70::/64" nixosIspB.sourcePrefixes);
    clabSimulatedIspModeled = clabIsp.mode == "nat66";
    clabSimulatedIspWarns = warningMentionsNat66 clabIsp;
    clabSimulatedIspSourceScope = hasAll normalClabPrefixes clabIsp.sourcePrefixes;
    clabSimulatedIspExcludesHostileUla = !(builtins.elem "fd42:dead:feed:70::/64" clabIsp.sourcePrefixes);
    hetzRoutedCoreHasNoNat66 = hetzCore == {};
  }
' > "${checks_json}"

failed_checks="$(jq -r 'to_entries[] | select(.value != true) | .key' "${checks_json}")"
if [[ -n "${failed_checks}" ]]; then
  echo "FAIL sigma-simulated-isp-nat66-contract" >&2
  echo "failed checks:" >&2
  while IFS= read -r failed_check; do
    echo "  ${failed_check}" >&2
  done <<< "${failed_checks}"
  gron "${output_json}" | rg 'egressIntent.nat66|router-core-isp|router-core-simulated|hetz-router-core' >&2 || true
  exit 1
fi

echo "PASS sigma-simulated-isp-nat66-contract"
