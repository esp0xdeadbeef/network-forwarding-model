#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
example_root="${repo_root}/../network-labs/examples"

fail() { echo "$1" >&2; exit 1; }

run_one() {
  local example_name="$1"
  local intent_path="${example_root}/${example_name}/intent.nix"

  [[ -f "${intent_path}" ]] || fail "missing intent.nix: ${intent_path}"

  local output_json
  output_json="$(mktemp)"
  trap 'rm -f "'"${output_json}"'"' RETURN

  nix run "${repo_root}#compile-and-build-forwarding-model" -- "${intent_path}" > "${output_json}"

  OUTPUT_JSON="${output_json}" nix eval --impure --expr '
    let
      data = builtins.fromJSON (builtins.readFile (builtins.getEnv "OUTPUT_JSON"));
      siteA = data.enterprise.enterpriseA.site."site-a";
      siteB = data.enterprise.enterpriseB.site."site-b";
      overlayA = siteA.overlayReachability."east-west";
      overlayB = siteB.overlayReachability."east-west";
      policyIfacesA = builtins.attrNames siteA.nodes."s-router-policy".interfaces;
      policyIfacesB = builtins.attrNames siteB.nodes."b-router-policy".interfaces;
    in
      overlayA.terminateOn == [ "s-router-core-isp-b" ]
      && overlayB.terminateOn == [ "b-router-core" ]
      && builtins.any (dst: dst == "10.60.10.0/24") (map (r: r.dst) overlayA.routes4)
      && builtins.any (dst: dst == "10.20.10.0/24") (map (r: r.dst) overlayB.routes4)
      && builtins.any
        (name: name == "p2p-s-router-policy-s-router-upstream-selector--access-s-router-access-admin--uplink-east-west")
        policyIfacesA
      && builtins.any
        (name: name == "p2p-b-router-policy-b-router-upstream-selector--access-b-router-access-branch--uplink-east-west")
        policyIfacesB
  ' >/dev/null || fail "FAIL ${example_name}: forwarding validation failed"

  echo "PASS ${example_name}"
  rm -f "${output_json}"
  trap - RETURN
}

run_one "dual-wan-branch-overlay"
run_one "dual-wan-branch-overlay-bgp"
