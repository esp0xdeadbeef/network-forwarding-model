#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: SMT-NFM-TRANSIT-DESERIALIZE-001
# GAMP-SCOPE: software-module-test

repo_root="$(git rev-parse --show-toplevel)"
source "${repo_root}/tests/lib/timing.sh"

start_ms="$(test_now_ms)"
tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

expr_nix="${tmpdir}/expr.nix"
cat >"${expr_nix}" <<'EOF'
let
  pkgs = import <nixpkgs> { };
  repoRoot = builtins.getEnv "REPO_ROOT";
  transitOrdering = import (repoRoot + "/implementation/s88/Site/transit-ordering.nix") {
    lib = pkgs.lib;
    self = { outPath = repoRoot; };
  };
  result = transitOrdering.canonicalize {
    siteName = "unit.test";
    pairs = [
      [ "core-provider" "access-handoff" ]
      [ "access-client" "downstream" ]
      [ "downstream" "policy" ]
      [ "policy" "upstream" ]
      [ "upstream" "core-wan" ]
    ];
    roleFromInput = node: {
      access-handoff = "access";
      access-client = "access";
      downstream = "downstream-selector";
      policy = "policy";
      upstream = "upstream-selector";
      core-provider = "core";
      core-wan = "core";
    }.${node} or null;
  };
in
  assert builtins.elem [ "access-handoff" "core-provider" ] result;
  result
EOF

REPO_ROOT="${repo_root}" nix eval --json --impure --file "${expr_nix}" \
  >/tmp/nfm-transit-ordering-deserializes-compiler-links.json

pass_timed "transit-ordering-deserializes-compiler-links" "${start_ms}"
