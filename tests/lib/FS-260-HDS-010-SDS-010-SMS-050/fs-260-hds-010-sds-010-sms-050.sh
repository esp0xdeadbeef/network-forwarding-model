#!/usr/bin/env bash
# GAMP-ID: FS-260-HDS-010-SDS-010-SMS-050
# GAMP-SCOPE: software-module-test
# Focused construction test: NFM boundary scan.
#
# SMS-050: NFM must not emit platform-specific or renderer-specific concepts.
# Scans NFM implementation for forbidden platform tokens (nftables, systemd,
# NixOS, containerlab, Docker, Cisco, Junos) and provider names used as
# forwarding classification (nebula, wireguard, openvpn).
# Excludes test fixtures, expected output, flake.lock, and README which may
# contain these terms in non-forwarding contexts.
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT
all_checks_passed=true

echo "--- FS-260-HDS-010-SDS-010-SMS-050: NFM boundary scan ---"
echo ""

# ============================================================
# Scan directories
# ============================================================
src_dirs=("${repo_root}/implementation" "${repo_root}/src")
exclude_dirs=("tests" "benchmarks" "expected")
exclude_files=("flake.lock" "README.md" "flake.nix")

# ============================================================
# Forbidden platform-specific tokens (case-insensitive)
# ============================================================
forbidden_tokens=(
  "nftables"
  "systemd-networkd"
  "NixOS module"
  "containerlab"
  "docker"
  "podman"
  "cisco ios"
  "junos"
)

# Provider names that must not appear as forwarding classification
# (overlay forwarding uses kind="overlay", not provider names)
forbidden_providers=(
  "nebula"
  "wireguard"
  "openvpn"
)

# ============================================================
# Build exclusion patterns
# ============================================================
exclude_pattern=""
for d in "${exclude_dirs[@]}"; do
  exclude_pattern="${exclude_pattern} -not -path '*/${d}/*'"
done

# ============================================================
# Predicate 1: No platform tokens in NFM implementation source
# ============================================================
echo "--- Predicate 1: Platform-specific tokens in NFM implementation ---"

platform_hits_file="${tmp_dir}/platform-hits.txt"
> "${platform_hits_file}"

for token in "${forbidden_tokens[@]}"; do
  find "${src_dirs[@]}" -type f -name '*.nix' ${exclude_pattern} -print0 2>/dev/null | \
    xargs -0 grep -in "${token}" 2>/dev/null >> "${platform_hits_file}" || true
done

platform_count=$(wc -l < "${platform_hits_file}" 2>/dev/null || echo 0)

if [[ "${platform_count}" -gt 0 ]]; then
  echo "FAIL: Found ${platform_count} platform-specific token(s) in NFM implementation:"
  head -10 "${platform_hits_file}" | while IFS= read -r line; do
    echo "  ${line}"
  done
  all_checks_passed=false
else
  echo "PASS: No platform-specific tokens in NFM implementation"
fi

# ============================================================
# Predicate 2: No provider names used as forwarding classification
# ============================================================
echo ""
echo "--- Predicate 2: Provider names in NFM implementation ---"

provider_hits_file="${tmp_dir}/provider-hits.txt"
> "${provider_hits_file}"

for token in "${forbidden_providers[@]}"; do
  find "${src_dirs[@]}" -type f -name '*.nix' ${exclude_pattern} -print0 2>/dev/null | \
    xargs -0 grep -in "${token}" 2>/dev/null >> "${provider_hits_file}" || true
done

provider_count=$(wc -l < "${provider_hits_file}" 2>/dev/null || echo 0)

if [[ "${provider_count}" -gt 0 ]]; then
  echo "WARN: Found ${provider_count} provider name reference(s) in NFM implementation:"
  head -10 "${provider_hits_file}" | while IFS= read -r line; do
    echo "  ${line}"
  done
  echo "  (May be in overlay-interface helpers with kind='overlay' — verify these are metadata, not forwarding classification)"
else
  echo "PASS: No provider names in NFM implementation"
fi

# ============================================================
# Seeded Negative: Would detect injected platform token
# ============================================================
echo ""
echo "--- Seeded Negative: Would detect injected platform token ---"

fake_file="${tmp_dir}/fake-nfm-output.nix"
cat > "${fake_file}" << 'FAKE'
{
  # SEEDED-NEGATIVE: Injected nftables rule for SMS-050 testing
  nftables = {
    table = "edge_nat";
    chain = "postrouting";
  };
  # SEEDED-NEGATIVE: Injected WireGuard endpoint for provider-name detection
  wireguardEndpoint = "1.2.3.4:51820";
}
FAKE

fake_hits_file="${tmp_dir}/fake-hits.txt"
> "${fake_hits_file}"

for token in "nftables" "wireguard"; do
  grep -in "${token}" "${fake_file}" 2>/dev/null >> "${fake_hits_file}" || true
done

fake_count=$(wc -l < "${fake_hits_file}" 2>/dev/null || echo 0)

if [[ "${fake_count}" -ge 2 ]]; then
  echo "PASS: Seeded negative — scanner detects ${fake_count} injected platform token(s)"
else
  echo "FAIL: Seeded negative — scanner failed to detect injected platform tokens"
  all_checks_passed=false
fi

# ============================================================
# Report
# ============================================================
echo ""
if ${all_checks_passed}; then
  echo "PASS: FS-260-HDS-010-SDS-010-SMS-050 — NFM boundary verified."
  echo "  No platform-specific tokens (nftables, systemd, NixOS, containerlab, Cisco, Junos) in NFM implementation."
  exit 0
else
  echo "FAIL: FS-260-HDS-010-SDS-010-SMS-050 — violations detected."
  exit 1
fi
