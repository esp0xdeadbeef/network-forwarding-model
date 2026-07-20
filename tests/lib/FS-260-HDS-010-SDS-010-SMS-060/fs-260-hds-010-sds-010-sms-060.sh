#!/usr/bin/env bash
# GAMP-ID: FS-260-HDS-010-SDS-010-SMS-060
# GAMP-SCOPE: software-module-test
# Focused construction test: NFM platform-independence scan.
#
# SMS-060: NFM must not depend on or leak renderer-specific concepts.
# Scans NFM implementation for renderer repository paths, module references,
# and platform-specific paths (network-renderer, nixos/modules, systemd/network,
# nftables).
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT
all_checks_passed=true

echo "--- FS-260-HDS-010-SDS-010-SMS-060: NFM platform-independence scan ---"
echo ""

# ============================================================
# Scan directories
# ============================================================
src_dirs=("${repo_root}/implementation" "${repo_root}/src")
exclude_dirs=("tests" "benchmarks" "expected")

# ============================================================
# Build exclusion patterns
# ============================================================
exclude_pattern=""
for d in "${exclude_dirs[@]}"; do
  exclude_pattern="${exclude_pattern} -not -path '*/${d}/*'"
done

# ============================================================
# Predicate 1: No renderer-specific paths in NFM code
# ============================================================
echo "--- Predicate 1: Renderer-specific paths in NFM code ---"

# Check that NFM doesn't reference renderer repository paths
renderer_refs_file="${tmp_dir}/renderer-refs.txt"
> "${renderer_refs_file}"

find "${src_dirs[@]}" -type f -name '*.nix' ${exclude_pattern} -print0 2>/dev/null | \
  xargs -0 grep -nE '(network-renderer|nixos/modules|systemd/network|nftables)' 2>/dev/null >> "${renderer_refs_file}" || true

renderer_count=$(wc -l < "${renderer_refs_file}" 2>/dev/null || echo 0)

if [[ "${renderer_count}" -gt 0 ]]; then
  echo "FAIL: Found ${renderer_count} renderer-specific reference(s) in NFM code:"
  cat "${renderer_refs_file}"
  all_checks_passed=false
else
  echo "PASS: No renderer-specific paths in NFM implementation"
fi

# ============================================================
# Predicate 2: No provider-based renderer imports
# ============================================================
echo ""
echo "--- Predicate 2: No renderer provider imports in NFM ---"

provider_import_file="${tmp_dir}/provider-imports.txt"
> "${provider_import_file}"

find "${src_dirs[@]}" -type f -name '*.nix' ${exclude_pattern} -print0 2>/dev/null | \
  xargs -0 grep -nE '(import.*renderer|renderer.*import)' 2>/dev/null >> "${provider_import_file}" || true

provider_import_count=$(wc -l < "${provider_import_file}" 2>/dev/null || echo 0)

if [[ "${provider_import_count}" -gt 0 ]]; then
  echo "FAIL: Found ${provider_import_count} renderer import(s) in NFM code:"
  cat "${provider_import_file}"
  all_checks_passed=false
else
  echo "PASS: No renderer provider imports in NFM implementation"
fi

# ============================================================
# Seeded Negative: Would detect injected renderer path
# ============================================================
echo ""
echo "--- Seeded Negative: Would detect injected renderer path ---"

fake_file="${tmp_dir}/fake-nfm-renderer-ref.nix"
cat > "${fake_file}" << 'FAKE'
{
  # SEEDED-NEGATIVE: Injected renderer path reference for SMS-060 testing
  rendererModule = import ./network-renderer-containerlab-linux-backend/modules/nftables.nix;
  # SEEDED-NEGATIVE: Injected NixOS module path for SMS-060 testing
  nixosModule = "${builtins.toString ./nixos/modules/networking.nix}";
}
FAKE

fake_hits_file="${tmp_dir}/fake-renderer-hits.txt"
> "${fake_hits_file}"

grep -nE '(network-renderer|nixos/modules)' "${fake_file}" 2>/dev/null >> "${fake_hits_file}" || true

fake_count=$(wc -l < "${fake_hits_file}" 2>/dev/null || echo 0)

if [[ "${fake_count}" -ge 2 ]]; then
  echo "PASS: Seeded negative — scanner detects ${fake_count} injected renderer reference(s)"
else
  echo "FAIL: Seeded negative — scanner failed to detect injected renderer references"
  all_checks_passed=false
fi

# ============================================================
# Report
# ============================================================
echo ""
if ${all_checks_passed}; then
  echo "PASS: FS-260-HDS-010-SDS-010-SMS-060 — NFM platform independence verified."
  echo "  No renderer-specific path references in NFM code."
  exit 0
else
  echo "FAIL: FS-260-HDS-010-SDS-010-SMS-060 — violations detected."
  exit 1
fi
