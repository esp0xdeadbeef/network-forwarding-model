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

eval_expr="
  let
    flake = builtins.getFlake \"path:${repo_root}\";
    out = flake.libBySystem.x86_64-linux.buildFromCompilerInputPath \"${intent}\";
  in
    builtins.length (builtins.attrNames (out.enterprise or {}))
"

# ── Concurrent-load isolation: prefire (warm Nix store) ──
# Populate the Nix store for the fixture before the timed evaluation so
# the timed window does not pay cold-store population cost under contention.
prefire_timeout_sec=120
prefire_start_ms="$(date +%s%3N)"
set +e
timeout "${prefire_timeout_sec}" \
  nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure \
    --expr "${eval_expr}" >/dev/null
prefire_rc=$?
set -e
prefire_end_ms="$(date +%s%3N)"
prefire_elapsed_ms=$((prefire_end_ms - prefire_start_ms))

if [[ ${prefire_rc} -ne 0 ]]; then
  echo "FAIL semantic lib performance boundary: prefire could not populate overlay example within ${prefire_elapsed_ms}ms (exit ${prefire_rc})" >&2
  exit "${prefire_rc}"
fi

# ── Timed evaluation with retry for store contention ──
run_timed_eval_with_retry() {
  local label="$1"
  local force_first_timeout="${2:-0}"
  local attempt=0
  local elapsed_ms=0
  local rc=1
  local start_ms
  local end_ms
  local timeout_sec
  local -a attempt_timeouts=(60 10)

  while [[ "${attempt}" -lt "${#attempt_timeouts[@]}" ]]; do
    timeout_sec="${attempt_timeouts[${attempt}]}"
    start_ms="$(date +%s%3N)"
    set +e
    if [[ "${force_first_timeout}" == "1" && "${attempt}" == "0" ]]; then
      timeout 1 bash -c 'sleep 2' >/dev/null
      rc=$?
    else
      timeout "${timeout_sec}" \
        nix eval \
          --extra-experimental-features 'nix-command flakes' \
          --impure \
          --expr "${eval_expr}" >/dev/null
      rc=$?
    fi
    set -e
    end_ms="$(date +%s%3N)"
    elapsed_ms=$((end_ms - start_ms))

    if [[ ${rc} -eq 0 ]]; then
      printf '%s\n' "${elapsed_ms}"
      return 0
    fi

    if [[ ${rc} -eq 124 ]]; then
      nix store ping >/dev/null 2>&1 || true
      sleep 2
      attempt=$((attempt + 1))
      continue
    fi

    echo "FAIL semantic lib performance boundary: ${label} overlay example semantic build failed after ${elapsed_ms}ms (exit ${rc})" >&2
    return "${rc}"
  done

  echo "FAIL semantic lib performance boundary: ${label} overlay example semantic build timed out after retry (last attempt ${elapsed_ms}ms)" >&2
  return 1
}

# Seeded negative: the first attempt times out, but the warm retry must pass.
run_timed_eval_with_retry "seeded-timeout-retry" 1 >/dev/null

if elapsed_ms="$(run_timed_eval_with_retry "real-boundary" 0)"; then
  echo "PASS semantic-lib-performance-boundary ${elapsed_ms}ms"
else
  exit "$?"
fi
