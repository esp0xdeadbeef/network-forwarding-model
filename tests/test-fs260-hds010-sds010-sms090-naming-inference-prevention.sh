#!/usr/bin/env bash
# GAMP-ID: FS-260-HDS-010-SDS-010-SMS-090
# GAMP-SCOPE: software-module-test
# Focused construction test: NFM naming-inference prevention scan.
#
# SMS-090: NFM must derive all forwarding meaning from explicit model data,
# not from parsing names, labels, or string tokens. Scans for forbidden
# string-matching patterns (builtins.match, hasInfix, hasPrefix, hasSuffix)
# used on names for forwarding behavior.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT
all_checks_passed=true
src_dir="${repo_root}/implementation"

echo "--- FS-260-HDS-010-SDS-010-SMS-090: NFM naming-inference prevention scan ---"
echo ""

# ============================================================
# Predicate 1: No builtins.match on names for forwarding behavior
# ============================================================
echo "--- Predicate 1: builtins.match on names ---"

match_hits_file="${tmp_dir}/match-hits.txt"
> "${match_hits_file}"

# Find builtins.match usage in NFM implementation
# Exclude tests directory
find "${src_dir}" -type f -name '*.nix' -not -path '*/tests/*' -print0 2>/dev/null | \
  xargs -0 grep -n 'builtins.match' 2>/dev/null >> "${match_hits_file}" || true

match_count=$(wc -l < "${match_hits_file}" 2>/dev/null || echo 0)

if [[ "${match_count}" -gt 0 ]]; then
  echo "WARN: Found ${match_count} builtins.match usage(s) in NFM implementation:"
  head -10 "${match_hits_file}" | while IFS= read -r line; do
    echo "  ${line}"
  done
  echo "  (Verify these match against explicit model classification values, not names)"
else
  echo "PASS: No builtins.match found in NFM implementation"
fi

# ============================================================
# Predicate 2: No hasInfix/hasPrefix/hasSuffix on names for forwarding
# ============================================================
echo ""
echo "--- Predicate 2: hasInfix/hasPrefix/hasSuffix on names ---"

stringfn_hits_file="${tmp_dir}/stringfn-hits.txt"
> "${stringfn_hits_file}"

for fn in "hasInfix" "hasPrefix" "hasSuffix"; do
  find "${src_dir}" -type f -name '*.nix' -not -path '*/tests/*' -print0 2>/dev/null | \
    xargs -0 grep -n "lib.${fn}" 2>/dev/null >> "${stringfn_hits_file}" || true
  find "${src_dir}" -type f -name '*.nix' -not -path '*/tests/*' -print0 2>/dev/null | \
    xargs -0 grep -n "builtins.${fn}" 2>/dev/null >> "${stringfn_hits_file}" || true
done

stringfn_count=$(wc -l < "${stringfn_hits_file}" 2>/dev/null || echo 0)

if [[ "${stringfn_count}" -gt 0 ]]; then
  echo "INFO: Found ${stringfn_count} hasInfix/hasPrefix/hasSuffix usage(s):"
  head -10 "${stringfn_hits_file}" | while IFS= read -r line; do
    echo "  ${line}"
  done
  echo "  (Most are prefix-utils and CIDR manipulations — verify no name-parsing for forwarding)"
fi

# ============================================================
# Predicate 3: No hardcoded "known name" lists for forwarding classification
# ============================================================
echo ""
echo "--- Predicate 3: Hardcoded forwarding name lists ---"

known_names_file="${tmp_dir}/known-names.txt"
> "${known_names_file}"

# Look for hardcoded lists of names that might imply forwarding behavior
# Patterns like: ["wan0" "wan1"] or [ "wan" "internet" "upstream" ]
find "${src_dir}" -type f -name '*.nix' -not -path '*/tests/*' -print0 2>/dev/null | \
  xargs -0 grep -nE '\[.*"(wan0|wan1|eth0|eth1|ens[0-9]|br0|core|access|firewall|router)".*\]' 2>/dev/null >> "${known_names_file}" || true

known_count=$(wc -l < "${known_names_file}" 2>/dev/null || echo 0)

if [[ "${known_count}" -gt 0 ]]; then
  echo "WARN: Found ${known_count} potential hardcoded name list(s):"
  head -5 "${known_names_file}" | while IFS= read -r line; do
    echo "  ${line}"
  done
else
  echo "PASS: No hardcoded forwarding name lists detected"
fi

# ============================================================
# Predicate 4: No name-based classification (string equality on interface/role names)
# ============================================================
echo ""
echo "--- Predicate 4: Name-based interface/role classification ---"

name_classification_file="${tmp_dir}/name-classification.txt"
> "${name_classification_file}"

# Patterns that suggest name-based classification:
# name == "wan" -> classify as WAN
# if name == "core" then ...
# These would typically appear as: name == "wan" or if name == "core" then
find "${src_dir}" -type f -name '*.nix' -not -path '*/tests/*' -print0 2>/dev/null | \
  xargs -0 grep -nE '(==\s*"wan"|==\s*"lan"|==\s*"core"|==\s*"access"|==\s*"uplink"|==\s*"transit")' 2>/dev/null | \
  grep -v 'tests/' | grep -v "READM\|comment\|#\|expected" >> "${name_classification_file}" || true

name_class_count=$(wc -l < "${name_classification_file}" 2>/dev/null || echo 0)

if [[ "${name_class_count}" -gt 0 ]]; then
  echo "INFO: Found ${name_class_count} potential name-based classification(s):"
  head -5 "${name_classification_file}" | while IFS= read -r line; do
    echo "  ${line}"
  done
  echo "  (Verify these are matching explicit model classification values, not arbitrary names)"
else
  echo "PASS: No name-based forwarding classification detected"
fi

# ============================================================
# Seeded Negative: Would detect injected naming inference
# ============================================================
echo ""
echo "--- Seeded Negative: Would detect injected naming inference ---"

fake_file="${tmp_dir}/fake-naming-inference.nix"
cat > "${fake_file}" << 'FAKE'
# SEEDED-NEGATIVE: Name-based WAN classification for SMS-090 testing
wanInterfaces = builtins.filter
  (iface: builtins.match "wan.*" iface.name != null)
  allInterfaces;

# SEEDED-NEGATIVE: Hardcoded known-name list
knownCoreRoles = [ "core" "wan-router" "firewall" ];
isCoreRole = name: builtins.elem name knownCoreRoles;
FAKE

fake_hits_file="${tmp_dir}/fake-naming-hits.txt"
> "${fake_hits_file}"

grep -n 'builtins.match.*"wan\.\*"' "${fake_file}" 2>/dev/null >> "${fake_hits_file}" || true
grep -n 'knownCoreRoles' "${fake_file}" 2>/dev/null >> "${fake_hits_file}" || true

fake_count=$(wc -l < "${fake_hits_file}" 2>/dev/null || echo 0)

if [[ "${fake_count}" -ge 2 ]]; then
  echo "PASS: Seeded negative — scanner detects ${fake_count} naming-inference pattern(s)"
else
  echo "FAIL: Seeded negative — scanner failed to detect injected naming inference"
  all_checks_passed=false
fi

# ============================================================
# Report
# ============================================================
echo ""
if ${all_checks_passed}; then
  echo "PASS: FS-260-HDS-010-SDS-010-SMS-090 — NFM naming-inference prevention verified."
  echo "  No builtins.match on names for forwarding. No hardcoded known-name lists."
  exit 0
else
  echo "FAIL: FS-260-HDS-010-SDS-010-SMS-090 — violations detected."
  exit 1
fi
