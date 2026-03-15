#!/usr/bin/env bash
set -euo pipefail
#nix run .#compile-and-solve -- ../network-compiler/examples/single-wan-with-nebula/inputs.nix
#nix run .#compile-and-solve -- ../network-compiler/examples/priority-stability/inputs.nix
#nix run .#compile-and-solve -- ../network-compiler/examples/overlay-east-west/inputs.nix
example_repo=$(nix eval --raw --impure --expr 'builtins.fetchGit { url = "git@github.com:esp0xdeadbeef/network-labs.git";}')

nix run .#compile-and-solve -- $example_repo/examples/overlay-east-west/intent.nix
