#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-985-HDS-010-SDS-010-SMS-010
# GAMP-SCOPE: software-module-test
#
# FS-985 Dependency Declaration Hygiene: a flake.nix input that references a
# network-* repository must use a floating ref (a branch such as `main`), never
# a hardcoded 40-hex revision. A hardcoded revision blocks
# `nix flake lock --update-input <input>` propagation: the command resolves the
# pin in flake.nix, not the branch tip, so upstream fixes silently never arrive.
#
# `flake.lock` is the sole authoritative revision-pinning surface (SMS-985
# responsibility 3), so this module asserts flake.nix only.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/timing.sh"
flake="${repo_root}/flake.nix"
tmpdir="$(mktemp -d -t fs985-sms010.XXXXXX)"
trap 'rm -rf "${tmpdir}"' EXIT

fail() {
  echo "FAIL FS-985-HDS-010-SDS-010-SMS-010: $*" >&2
  exit 1
}

[[ -f "${flake}" ]] || fail "missing ${flake}"

# A network-* input with an embedded revision: github:owner/network-thing/<40 hex>
pinned_network_re='github:[A-Za-z0-9._-]+/network-[A-Za-z0-9._-]+/[0-9a-f]{40}'
# Also catch the bare-revision shorthand `github:owner/network-thing/<rev>` where
# the revision is expressed as an explicit `rev = "..."` attribute alongside url.
scan_flake() {
  local file="$1"
  rg --no-heading --line-number --with-filename \
    --regexp "${pinned_network_re}" \
    --regexp 'rev[[:space:]]*=[[:space:]]*"[0-9a-f]{40}"' \
    "${file}" 2>/dev/null || true
}

# ---- Positive: the live flake.nix must use floating refs --------------------
hits="$(scan_flake "${flake}")"
if [[ -n "${hits}" ]]; then
  echo "FAIL FS-985-HDS-010-SDS-010-SMS-010: network-* inputs must use floating refs, not revisions." >&2
  echo "FAIL FS-985-HDS-010-SDS-010-SMS-010: pin the revision in flake.lock instead; flake.nix uses main." >&2
  printf '%s\n' "${hits}" | sed "s#${repo_root}/##; s/^/FAIL FS-985-HDS-010-SDS-010-SMS-010:   /" >&2
  exit 1
fi

# ---- Seeded negative: an injected revision pin must be detected -------------
cat >"${tmpdir}/pinned.nix" <<'NIX'
{
  inputs."network-forwarding-model".url =
    "github:esp0xdeadbeef/network-forwarding-model/626ad6ed985234fbeaac0a2b1e9c9001d673e6fb";
}
NIX

if [[ -z "$(scan_flake "${tmpdir}/pinned.nix")" ]]; then
  fail "seeded negative not detected: injected 40-hex network-* revision pin passed"
fi

# ---- Seeded negative: explicit rev attribute is also rejected ---------------
cat >"${tmpdir}/rev-attr.nix" <<'NIX'
{
  inputs."network-labs" = {
    url = "github:esp0xdeadbeef/network-labs";
    rev = "0123456789abcdef0123456789abcdef01234567";
  };
}
NIX

if [[ -z "$(scan_flake "${tmpdir}/rev-attr.nix")" ]]; then
  fail "seeded negative not detected: explicit 40-hex rev attribute passed"
fi

# ---- Recovery: restoring a floating ref clears the violation ----------------
sed 's#/626ad6ed985234fbeaac0a2b1e9c9001d673e6fb#/main#' "${tmpdir}/pinned.nix" >"${tmpdir}/recovered.nix"
if [[ -n "$(scan_flake "${tmpdir}/recovered.nix")" ]]; then
  fail "recovery did not clear the pin: floating ref still reported as pinned"
fi

pass_timed "fs985-flake-input-floating-refs"
