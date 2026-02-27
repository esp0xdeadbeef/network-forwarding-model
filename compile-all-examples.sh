# ./compile-all-examples.sh
#!/usr/bin/env bash
set -euo pipefail

# Use temporary git config to safely allow all /nix/store repos
export GIT_CONFIG_GLOBAL="$(mktemp)"
cat > "$GIT_CONFIG_GLOBAL" <<'EOF'
[safe]
  directory = /nix/store
  directory = /nix/store/*
  directory = *
EOF

find ../network-compiler/examples -type f -exec sh -c '
  echo -e "\n\n$1:\n"
  nix run .#compile-and-solve -- "$1" | jq -c
' _ {} \;
