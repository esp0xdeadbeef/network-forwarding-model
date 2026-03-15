#!/usr/bin/env bash
set -euo pipefail

export GIT_CONFIG_GLOBAL="$(mktemp)"
trap 'rm -f "$GIT_CONFIG_GLOBAL"' EXIT
cat >"$GIT_CONFIG_GLOBAL" <<'EOF'
[safe]
  directory = *
EOF
example_repo=$(nix eval --raw --impure --expr 'builtins.fetchGit { url = "git@github.com:esp0xdeadbeef/network-labs.git";}')

find $example_repo/examples -type f -exec sh -c '
  printf "\n\n%s:\n\n" "$1"
  nix run .#compile-and-solve -- "$1" | jq -c
' _ {} \;
