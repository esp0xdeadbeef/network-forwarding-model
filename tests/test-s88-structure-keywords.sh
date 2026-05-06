#!/usr/bin/env bash
set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

matches_file="${tmp_dir}/s88-keyword-matches.tsv"
: >"${matches_file}"
import_line_re='(^|[[:space:]=({])import[[:space:]]'

fail() {
  printf 'FAIL s88-structure-keywords: %s\n' "$*" >&2
}

scan_group() {
  local group="$1"
  local pattern="$2"

  rg \
    --no-heading \
    --line-number \
    --with-filename \
    --ignore-case \
    --glob '!fixtures/**' \
    --glob '!result/**' \
    --glob '!result-*' \
    --glob '!*.lock' \
    --glob '!*.json' \
    --glob '!*.jsonl' \
    --glob '!*.tsv' \
    --glob '!tests/test-s88-structure-keywords.sh' \
    --regexp "${pattern}" \
    "${repo_root}/s88" \
    "${repo_root}/lib" \
    2>/dev/null \
    | while IFS=: read -r file line text; do
        if [[ "${text}" =~ ^[[:space:]]*(source|\.|#include)[[:space:]] ]]; then
          continue
        fi
        if [[ "${text}" =~ ${import_line_re} ]]; then
          continue
        fi
        file="${file#"${repo_root}/"}"
        printf '%s\t%s\t%s\t%s\n' "${group}" "${file}" "${line}" "${text}"
      done >>"${matches_file}" || true
}

scan_group \
  "role-or-structure-keyword" \
  '\b(access|policy|upstream-selector|downstream-selector|core|selector|logicalNode|forwardingSemantics|controlModule|equipmentModule)\b'

scan_group \
  "abbreviation-or-protocol" \
  '\b(s88|p2p|bgp|dns|mdns|wan|lan|nat|ipam|ra|pd|asn|rr|vrf|vlan|fw|cidr|ipv4|ipv6|gua|ula|dhcp|dhcpv6|dhcp6|slaac|mtu)\b'

scan_group \
  "example-or-site-identity" \
  '\b(esp0xdeadbeef|enterpriseA|enterpriseB|espbranch|acme|globex|ams|nyc|lon|site-a|site-b|site-c|s-router|b-router|c-router|hetzner|nebula|hostile|branch|s-sigma|lab-s-sigma)\b'

scan_group \
  "tenant-zone-or-service-name" \
  '\b(tenant|tenants|tenant-a|tenant-b|mgmt|admin|client|client2|clients|dmz|iot|printer|nas|streaming|guest|users|jump-host|admin-web|site-dns|site-dns-mgmt|sitec-dns-dmz|sitec-public-dns|sitec-dns-mgmt|dns-site|ntp-site|dmz-nebula|web01|nebula01)\b'

scan_group \
  "lane-uplink-or-egress-name" \
  '\b(uplink|uplinks|underlay|overlay|east-west|site-c-storage|wan-core|isp-a|isp-b|simulated-isp|public-egress|default-reachability|internal-reachability|overlay-reachability|delegated-public-egress|explicit-egress-default|local-access|overlay-core|service-dns)\b'

scan_group \
  "generated-id-or-name-parser" \
  '("|'\''|`)?(link::|adj::|overlay::|access::|uplink::|--access-|--uplink-|p2p-|core-|policy-|access-|upstream-|downstream-|site[a-z0-9-]*-|enterprise[A-Za-z0-9-]*-)'

scan_group \
  "string-parsing-primitive" \
  '\b(builtins\.match|builtins\.split|splitCIDR|elemAt|hasInfix|hasPrefix|hasSuffix|containsToken|suffixAfter|replaceStrings|sub\(|match\(|grep -F|grep -E|grep -q|rg )\b'

if [[ ! -s "${matches_file}" ]]; then
  echo "PASS s88-structure-keywords"
  exit 0
fi

fail "domain role words, abbreviations, concrete lab identities, generated-name fragments, or parser primitives were found in implementation files outside include statements."
fail "Implement the S88-style structure before this test may pass; regression.md may not waive this guard."
fail "Repeated tokens such as access/policy/core/upstream-selector/downstream-selector, protocol abbreviations, tenant/service names, lane/uplink names, and example identities like esp0xdeadbeef are structural coupling, not harmless naming."
fail "This is a hard failure because scattered keyword parsing can miss compiled output families, lanes, and policy rows when the model shape changes."

awk -F '\t' '
  {
    groupCount[$1]++;
    fileCount[$2]++;
  }
  END {
    print "FAIL s88-structure-keywords: grouped match counts:" > "/dev/stderr";
    for (group in groupCount) {
      printf "FAIL s88-structure-keywords:   %s\t%d\n", group, groupCount[group] > "/dev/stderr";
    }
    print "FAIL s88-structure-keywords: files with matches:" > "/dev/stderr";
    for (file in fileCount) {
      printf "FAIL s88-structure-keywords:   %s\t%d\n", file, fileCount[file] > "/dev/stderr";
    }
  }
' "${matches_file}"

fail "full match list follows: group<TAB>file<TAB>line<TAB>text"
sed 's/^/FAIL s88-structure-keywords:   /' "${matches_file}" >&2
exit 1
