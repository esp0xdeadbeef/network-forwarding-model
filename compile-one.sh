#!/usr/bin/env bash
set -euo pipefail
nix run .#compile-and-solve -- ../network-compiler/examples/single-wan-with-nebula/inputs.nix
