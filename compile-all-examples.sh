#!/usr/bin/env bash
set -euo pipefail

export GIT_CONFIG_GLOBAL="$(mktemp)"
trap 'rm -f "$GIT_CONFIG_GLOBAL"' EXIT
cat >"$GIT_CONFIG_GLOBAL" <<'EOF'
[safe]
  directory = *
EOF
#example_repo=$(nix eval --raw --impure --expr 'builtins.fetchGit { url = "git@github.com:esp0xdeadbeef/network-labs.git";}')
example_repo=$(nix flake prefetch github:esp0xdeadbeef/network-labs --json | jq -r .storePath)
example_repo=$(echo "../network-labs")

find "$example_repo/examples" -name 'intent.nix' -type f -exec sh -c '
  printf "\n\n%s:\n\n" "$1"
  nix run .#compile-and-build-forwarding-model -- "$1" | jq -c
' _ {} \;
