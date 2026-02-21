#!/usr/bin/env bash
nix eval \
  --impure \
  --expr "let sopsData = {}; in import ./dev/debug-lib/91-node-context.nix { inherit sopsData; nodeName = \"s-router-core-isp-1\"; }" \
  --json | jq
nix eval \
  --impure \
  --expr "let sopsData = {}; in import ./dev/debug-lib/91-node-context.nix { inherit sopsData; nodeName = \"s-router-policy-only\"; }" \
  --json | jq
nix eval \
  --impure \
  --expr "let sopsData = {}; in import ./dev/debug-lib/91-node-context.nix { inherit sopsData; nodeName = \"s-router-access-20\"; }" \
  --json | jq
nix eval \
  --impure \
  --expr "let sopsData = {}; in import ./dev/debug-lib/91-node-context.nix { inherit sopsData; nodeName = \"s-router-core-nebula-20\"; }" \
  --json | jq
