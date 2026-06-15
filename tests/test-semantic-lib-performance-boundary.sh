#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if awk '
  /mkSystemLib =/ { in_fn = 1 }
  in_fn && /applyForwardingModel =/ { in_apply = 1 }
  in_apply && /lib = pkgs\.lib/ { found = 1 }
  in_apply && /};/ { in_apply = 0 }
  in_fn && /^      packages =/ { in_fn = 0 }
  END { exit found ? 0 : 1 }
' "${repo_root}/flake.nix"; then
  cat >&2 <<'EOF'
FAIL semantic lib performance boundary: model evaluation imports pkgs.lib.

The semantic library path must use flake-provided nixpkgs.lib and
nixpkgs-network.lib.network directly. Importing a full package set pulls
Nixpkgs/stdenv evaluation into the FS-940 semantic compile path.
EOF
  exit 1
fi

intent="${repo_root}/tests/fixtures/examples/s-router-overlay-dns-lane-policy/intent.nix"

start_ms="$(date +%s%3N)"
timeout 10 \
  nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure \
    --expr "
      let
        flake = builtins.getFlake \"path:${repo_root}\";
        out = flake.libBySystem.x86_64-linux.buildFromCompilerInputPath \"${intent}\";
      in
        builtins.length (builtins.attrNames (out.enterprise or {}))
    " >/dev/null
rc=$?
end_ms="$(date +%s%3N)"
elapsed_ms=$((end_ms - start_ms))

if [[ "${rc}" -ne 0 ]]; then
  echo "FAIL semantic lib performance boundary: overlay example semantic build timed out or failed after ${elapsed_ms}ms" >&2
  exit "${rc}"
fi

echo "PASS semantic-lib-performance-boundary ${elapsed_ms}ms"
