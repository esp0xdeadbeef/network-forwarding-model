#!/usr/bin/env bash
set -euo pipefail

compiler_repo=$(nix flake metadata --json . | jq -r '.locks.nodes."network-compiler".locked | "github:\(.owner)/\(.repo)/\(.rev)"' | xargs nix flake prefetch --json | jq -r .storePath)
example_repo=$(nix flake prefetch github:esp0xdeadbeef/network-labs --json | jq -r .storePath)

test -d "$compiler_repo"
nix run .#compile-and-build-forwarding-model -- "$example_repo/examples/tri-site-dual-wan-overlay-integration-bgp/intent.nix"
