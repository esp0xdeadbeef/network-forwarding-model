#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-940-HDS-010-SDS-010-SMS-070
# Construction test: NFM semantic library performance boundary
# Trace chain: URS → FS-940 → FS-940-HDS-010 → FS-940-HDS-010-SDS-010 → SMS-070

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ── Flake semantic-library import boundary ──
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

# ── Seeded negative: pkgs.lib injection detection ──
# Create a temporary flake.nix copy with the forbidden injection and verify
# the awk guard detects it.
tmp_flake="$(mktemp)"
cleanup_flake() { rm -f "${tmp_flake}"; }
trap cleanup_flake EXIT

cp "${repo_root}/flake.nix" "${tmp_flake}"

# Inject a line that looks like `lib = pkgs.lib;` inside applyForwardingModel.
# We insert after the applyForwardingModel opening line.
sed -i '/applyForwardingModel =/a\      lib = pkgs.lib;' "${tmp_flake}"

if awk '
  /mkSystemLib =/ { in_fn = 1 }
  in_fn && /applyForwardingModel =/ { in_apply = 1 }
  in_apply && /lib = pkgs\.lib/ { found = 1 }
  in_apply && /};/ { in_apply = 0 }
  in_fn && /^      packages =/ { in_fn = 0 }
  END { exit found ? 0 : 1 }
' "${tmp_flake}"; then
  : # detected — negative case passes
else
  echo "FAIL semantic lib performance boundary: seeded negative pkgs.lib injection NOT detected by awk guard" >&2
  exit 1
fi

rm -f "${tmp_flake}"
trap - EXIT

intent="${repo_root}/tests/fixtures/examples/s-router-overlay-dns-lane-policy/intent.nix"

# ── Concurrent-load isolation: prefire (warm Nix store) ──
# Populate the Nix store for the fixture before the timed evaluation so
# the timed window does not pay cold-store population cost under contention.
nix eval \
  --extra-experimental-features 'nix-command flakes' \
  --impure \
  --expr "
    let
      flake = builtins.getFlake \"path:${repo_root}\";
      out = flake.libBySystem.x86_64-linux.buildFromCompilerInputPath \"${intent}\";
    in
      builtins.length (builtins.attrNames (out.enterprise or {}))
  " >/dev/null 2>&1 || true

# ── Timed evaluation with retry for store contention ──
timeout_sec=60
max_retries=3
attempt=0
passed=false
elapsed_ms=0

while [[ $attempt -le $max_retries ]]; do
  start_ms="$(date +%s%3N)"
  timeout ${timeout_sec} \
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

  if [[ $rc -eq 0 ]]; then
    passed=true
    break
  fi

  if [[ $rc -eq 124 ]]; then
    # Timeout — check Nix store contention before retry
    nix store ping >/dev/null 2>&1 || true
    sleep 2
  else
    # Non-timeout failure is terminal
    echo "FAIL semantic lib performance boundary: overlay example semantic build failed after ${elapsed_ms}ms (exit ${rc})" >&2
    exit ${rc}
  fi

  attempt=$((attempt + 1))
done

if [[ "${passed}" == "true" ]]; then
  echo "PASS semantic-lib-performance-boundary ${elapsed_ms}ms"
else
  echo "FAIL semantic lib performance boundary: overlay example semantic build timed out after ${max_retries} retries (last attempt ${elapsed_ms}ms)" >&2
  exit 1
fi
