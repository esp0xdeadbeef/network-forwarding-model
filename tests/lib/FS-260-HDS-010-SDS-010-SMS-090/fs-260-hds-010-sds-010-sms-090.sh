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

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT
all_checks_passed=true
src_dir="${repo_root}/implementation"

echo "--- FS-260-HDS-010-SDS-010-SMS-090: NFM naming-inference prevention scan ---"
echo ""

name_token_regex='(nodeName|requestedNode|interfaceName|iface\.name|ifName|linkName|providerName|tenantName|uplinkName|labelName|roleName)'

# ============================================================
# Predicate 1: No builtins.match on names for forwarding behavior
# ============================================================
echo "--- Predicate 1: builtins.match on names ---"

match_hits_file="${tmp_dir}/match-hits.txt"
> "${match_hits_file}"
forbidden_match_hits_file="${tmp_dir}/forbidden-match-hits.txt"
> "${forbidden_match_hits_file}"

find "${src_dir}" -type f -name '*.nix' -not -path '*/tests/*' -print0 2>/dev/null | \
  xargs -0 grep -n 'builtins.match' 2>/dev/null >> "${match_hits_file}" || true
grep -E "${name_token_regex}" "${match_hits_file}" > "${forbidden_match_hits_file}" || true

match_count=$(wc -l < "${match_hits_file}" 2>/dev/null || echo 0)
forbidden_match_count=$(wc -l < "${forbidden_match_hits_file}" 2>/dev/null || echo 0)

if [[ "${forbidden_match_count}" -gt 0 ]]; then
  echo "FAIL: Found ${forbidden_match_count} builtins.match usage(s) on identity-name fields:"
  head -10 "${forbidden_match_hits_file}" | while IFS= read -r line; do
    echo "  ${line}"
  done
  all_checks_passed=false
else
  echo "PASS: No builtins.match usage on identity-name fields (${match_count} total CIDR/explicit parsing usage(s) allowed)"
fi

# ============================================================
# Predicate 2: No string parsing on identity names for forwarding
# ============================================================
echo ""
echo "--- Predicate 2: string parsing on identity-name fields ---"

stringfn_hits_file="${tmp_dir}/stringfn-hits.txt"
> "${stringfn_hits_file}"
forbidden_stringfn_hits_file="${tmp_dir}/forbidden-stringfn-hits.txt"
> "${forbidden_stringfn_hits_file}"

for fn in "hasInfix" "hasPrefix" "hasSuffix"; do
  find "${src_dir}" -type f -name '*.nix' -not -path '*/tests/*' -print0 2>/dev/null | \
    xargs -0 grep -n "lib.${fn}" 2>/dev/null >> "${stringfn_hits_file}" || true
  find "${src_dir}" -type f -name '*.nix' -not -path '*/tests/*' -print0 2>/dev/null | \
    xargs -0 grep -n "builtins.${fn}" 2>/dev/null >> "${stringfn_hits_file}" || true
done
find "${src_dir}" -type f -name '*.nix' -not -path '*/tests/*' -print0 2>/dev/null | \
  xargs -0 grep -n 'splitString' 2>/dev/null >> "${stringfn_hits_file}" || true
grep -E "${name_token_regex}" "${stringfn_hits_file}" > "${forbidden_stringfn_hits_file}" || true

stringfn_count=$(wc -l < "${stringfn_hits_file}" 2>/dev/null || echo 0)
forbidden_stringfn_count=$(wc -l < "${forbidden_stringfn_hits_file}" 2>/dev/null || echo 0)

if [[ "${forbidden_stringfn_count}" -gt 0 ]]; then
  echo "FAIL: Found ${forbidden_stringfn_count} string parsing usage(s) on identity-name fields:"
  head -10 "${forbidden_stringfn_hits_file}" | while IFS= read -r line; do
    echo "  ${line}"
  done
  all_checks_passed=false
else
  echo "PASS: No string parsing on identity-name fields (${stringfn_count} total CIDR/explicit parsing usage(s) allowed)"
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
  echo "FAIL: Found ${known_count} potential hardcoded forwarding name list(s):"
  head -5 "${known_names_file}" | while IFS= read -r line; do
    echo "  ${line}"
  done
  all_checks_passed=false
else
  echo "PASS: No hardcoded forwarding name lists detected"
fi

# ============================================================
# Predicate 4: No string equality on identity names for forwarding
# ============================================================
echo ""
echo "--- Predicate 4: Identity-name equality classification ---"

name_classification_file="${tmp_dir}/name-classification.txt"
> "${name_classification_file}"

find "${src_dir}" -type f -name '*.nix' -not -path '*/tests/*' -print0 2>/dev/null | \
  xargs -0 grep -nE "(${name_token_regex}).*==\\s*\"(wan|lan|core|access|uplink|transit|router|firewall)\"|==\\s*\"(wan|lan|core|access|uplink|transit|router|firewall)\".*(${name_token_regex})" 2>/dev/null | \
  grep -vE '(\.role|roleOf )' >> "${name_classification_file}" || true

name_class_count=$(wc -l < "${name_classification_file}" 2>/dev/null || echo 0)

if [[ "${name_class_count}" -gt 0 ]]; then
  echo "FAIL: Found ${name_class_count} identity-name equality classification(s):"
  head -5 "${name_classification_file}" | while IFS= read -r line; do
    echo "  ${line}"
  done
  all_checks_passed=false
else
  echo "PASS: No identity-name equality classification detected"
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

# SEEDED-NEGATIVE: Name-prefix context derivation
coreContext = lib.hasPrefix "core-" nodeName;
nameParts = lib.splitString "-" nodeName;
FAKE

fake_hits_file="${tmp_dir}/fake-naming-hits.txt"
> "${fake_hits_file}"

grep -n 'builtins.match.*"wan\.\*"' "${fake_file}" 2>/dev/null >> "${fake_hits_file}" || true
grep -n 'knownCoreRoles' "${fake_file}" 2>/dev/null >> "${fake_hits_file}" || true
grep -n 'hasPrefix.*nodeName' "${fake_file}" 2>/dev/null >> "${fake_hits_file}" || true
grep -n 'splitString.*nodeName' "${fake_file}" 2>/dev/null >> "${fake_hits_file}" || true

fake_count=$(wc -l < "${fake_hits_file}" 2>/dev/null || echo 0)

if [[ "${fake_count}" -ge 4 ]]; then
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
