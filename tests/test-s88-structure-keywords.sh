#!/usr/bin/env bash
set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
regression_file="${repo_root}/regression.md"
start_marker="<!-- s88-keyword-boundary:start -->"
end_marker="<!-- s88-keyword-boundary:end -->"

fail() {
  printf 'FAIL s88-structure-keywords\n' >&2
  if [ "${1-}" != "" ]; then
    printf '%s\n' "$1" >&2
  fi
  exit 1
}

is_allowed_owner() {
  case "$1" in
    lib/fabric/transit-role-stages.nix) return 0 ;;
    lib/fabric/invariants/node-roles.nix) return 0 ;;
    lib/fabric/invariants/node-roles/*) return 0 ;;
    lib/fabric/invariants/transit-ordering-valid.nix) return 0 ;;
    src/solver/site/roles.nix) return 0 ;;
    src/solver/site/roles/*) return 0 ;;
    src/solver/site/topology/role-capabilities.nix) return 0 ;;
    src/solver/site/topology/semantic-node.nix) return 0 ;;
    src/solver/site/topology/semantic-selection.nix) return 0 ;;
    src/solver/site/topology/semantics.nix) return 0 ;;
    src/solver/site/topology/lane-access-uplinks.nix) return 0 ;;
    src/solver/site/topology/lane-core-uplinks.nix) return 0 ;;
    src/solver/site/topology/lane-links.nix) return 0 ;;
    *) return 1 ;;
  esac
}

awk -v start="$start_marker" -v end="$end_marker" '
  $0 == start { in_block = 1; next }
  $0 == end { in_block = 0; next }
  in_block && NF {
    print
  }
' "$regression_file" > "${TMPDIR:-/tmp}/s88-keyword-boundary.$$"
trap 'rm -f "${TMPDIR:-/tmp}/s88-keyword-boundary.$$"' EXIT
documented_file="${TMPDIR:-/tmp}/s88-keyword-boundary.$$"

if [ ! -s "$documented_file" ]; then
  fail "missing ${start_marker} regression block"
fi

declare -A documented=()
while IFS= read -r line; do
  case "$line" in
    *" | state=warn | reason="*)
      path="${line%% | state=warn | reason=*}"
      reason="${line#* | state=warn | reason=}"
      if [ "${#reason}" -lt 60 ]; then
        fail "S88 keyword exception for ${path} needs a concrete reason, not a label"
      fi
      documented["$path"]=1
      ;;
    *)
      fail "bad S88 keyword exception format: ${line}"
      ;;
  esac
done < "$documented_file"

mapfile -t source_files < <(
  find "$repo_root/src" "$repo_root/lib" -type f -name '*.nix' \
    | sed "s#^${repo_root}/##" \
    | sort
)

pattern='(^|[^[:alnum:]_-])(access|policy|upstream-selector|downstream-selector|core|access[A-Z][[:alnum:]_]*|policy[A-Z][[:alnum:]_]*|core[A-Z][[:alnum:]_]*|upstreamSelector[A-Z]?[[:alnum:]_]*|downstreamSelector[A-Z]?[[:alnum:]_]*|ds[A-Z][[:alnum:]_]*|us[A-Z][[:alnum:]_]*|esp0xdeadbeef|espbranch|s-router)([^[:alnum:]_-]|$)'
stale=()
warnings=()
undocumented=()

for rel in "${source_files[@]}"; do
  if is_allowed_owner "$rel"; then
    continue
  fi

  if rg -n --pcre2 "$pattern" "$repo_root/$rel" >/tmp/s88-keyword-hits.$$; then
    hit_count="$(wc -l < /tmp/s88-keyword-hits.$$ | tr -d ' ')"
    if [ "${documented[$rel]-}" = 1 ]; then
      warnings+=("WARN s88-structure-keywords:documented:${rel} hits=${hit_count}")
    else
      warnings+=("WARN s88-structure-keywords:undocumented:${rel} hits=${hit_count} action=implement-s88-structure-or-add-real-regression-reason")
      undocumented+=("$rel")
    fi
  fi
done
rm -f /tmp/s88-keyword-hits.$$

for path in "${!documented[@]}"; do
  found=0
  for rel in "${source_files[@]}"; do
    if [ "$rel" = "$path" ]; then
      found=1
      break
    fi
  done
  if [ "$found" = 0 ]; then
    stale+=("$path")
  fi
done

if [ "${#stale[@]}" -gt 0 ]; then
  fail "stale S88 keyword exception(s): ${stale[*]}"
fi

printf '%s\n' "${warnings[@]}"
if [ "${#undocumented[@]}" -gt 0 ]; then
  fail "undocumented S88 stage keyword leakage in: ${undocumented[*]}"
fi

printf 'PASS s88-structure-keywords\n'
