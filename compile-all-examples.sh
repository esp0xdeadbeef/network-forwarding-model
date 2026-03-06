# ./compile-all-examples.sh
#!/usr/bin/env bash
set -euo pipefail

export GIT_CONFIG_GLOBAL="$(mktemp)"
trap 'rm -f "$GIT_CONFIG_GLOBAL"' EXIT
cat >"$GIT_CONFIG_GLOBAL" <<'EOF'
[safe]
  directory = *
EOF

find ../network-compiler/examples -type f -exec sh -c '
  printf "\n\n%s:\n\n" "$1"
  nix run .#compile-and-solve -- "$1" | jq -c
' _ {} \;
