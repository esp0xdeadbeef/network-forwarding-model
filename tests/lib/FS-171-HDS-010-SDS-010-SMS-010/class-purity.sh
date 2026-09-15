#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-171-HDS-010-SDS-010-SMS-010
# GAMP-SCOPE: software-module-test
# Construction test: the forwarding model consumes compiler-emitted fields only.
# It shall not read meta.provenance.originalInputs (the raw intent copy).

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/timing.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT
export NFM_REPO_ROOT="${repo_root}"

# normalizeSites is the forwarding-model input boundary. Feed it a compiler
# shape where the site carries an explicit normalized `relations` field and the
# raw copy lives ONLY under meta.provenance.originalInputs. The boundary must
# use the compiler field and must not read the raw copy.
normalize_sites() {
  local input_json="$1"
  local out="$tmpdir/input.json"
  printf '%s' "$input_json" >"$out"
  NFM_INPUT_FILE="$out" nix eval --impure --json --expr '
    let
      repoRoot = builtins.getEnv "NFM_REPO_ROOT";
      input = builtins.fromJSON (builtins.readFile (builtins.getEnv "NFM_INPUT_FILE"));
      lib = (import (builtins.getFlake "github:NixOS/nixpkgs/0182a361324364ae3f436a63005877674cf45efb") { }).lib;
      normalizeSites = import (repoRoot + "/compiler-input/sites/build.nix") { inherit lib; self = { outPath = repoRoot; }; };
    in normalizeSites { config = input; }
  ' 2>&1
}

# P1: a compiler-shaped site builds from the compiler field; the raw-only key
# in meta.provenance.originalInputs is not required and not read.
p1_input='{
  "sites": { "ent": { "site-a": { "topology": { "nodes": {}, "links": [] }, "relations": [] } } },
  "meta": { "provenance": { "originalInputs": { "ent": { "site-a": { "communicationContract": { "relations": [] }, "ownership": {}, "pools": {}, "transport": {} } } } } }
}'
p1_out="$(normalize_sites "$p1_input")" || {
  printf 'FAIL [P1]: compiler-shaped site failed to normalize: %s\n' "$p1_out" >&2
  exit 1
}
grep -Fq "ent" <<<"$p1_out" || {
  printf 'FAIL [P1]: normalized sites missing enterprise: %s\n' "$p1_out" >&2
  exit 1
}
echo "PASS [P1]: compiler-shaped site normalizes without the raw-intent copy"

# P2: the raw copy is NOT the source of site membership. A site present ONLY in
# meta.provenance.originalInputs (absent from compiler output) must not appear.
p2_input='{
  "sites": { "ent": { "site-a": { "topology": { "nodes": {}, "links": [] }, "relations": [] } } },
  "meta": { "provenance": { "originalInputs": { "ent": { "site-raw-only": { "topology": {}, "relations": [] } } } } }
}'
p2_out="$(normalize_sites "$p2_input")" || {
  printf 'FAIL [P2]: normalization failed: %s\n' "$p2_out" >&2
  exit 1
}
if grep -Fq "site-raw-only" <<<"$p2_out"; then
  printf 'FAIL [P2]: raw-intent-only site leaked into the model: %s\n' "$p2_out" >&2
  exit 1
fi
echo "PASS [P2]: raw-intent-only site is not read"

echo "PASS FS-171-HDS-010-SDS-010-SMS-010 forwarding-model class purity"
