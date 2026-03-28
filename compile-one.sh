#!/usr/bin/env bash
set -euo pipefail
#nix run .#compile-and-solve -- ../network-compiler/examples/single-wan-with-nebula/inputs.nix
#nix run .#compile-and-solve -- ../network-compiler/examples/priority-stability/inputs.nix
#nix run .#compile-and-solve -- ../network-compiler/examples/overlay-east-west/inputs.nix
example_repo=$(nix flake prefetch github:esp0xdeadbeef/network-labs --json | jq -r .storePath)

#nix run .#compile-and-build-forwarding-model -- "$example_repo/examples/single-wan-with-nebula-any-to-any-fw/intent.nix"
nix run .#compile-and-build-forwarding-model -- "$example_repo/examples/single-wan/intent.nix"
