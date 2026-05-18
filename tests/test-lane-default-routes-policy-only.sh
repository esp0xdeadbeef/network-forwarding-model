#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
source "${repo_root}/tests/lib/timing.sh"
archive_json="$(mktemp)"
out_dir="$(mktemp -d)"
violations="$(mktemp)"
trap 'rm -f "${archive_json}" "${violations}"; rm -rf "${out_dir}"' EXIT
max_jobs="${TEST_JOBS:-$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN)}"
if ! [[ "${max_jobs}" =~ ^[0-9]+$ ]] || [ "${max_jobs}" -lt 1 ]; then
  max_jobs=1
fi

nix flake archive --json "path:${repo_root}" >"${archive_json}"

examples_root="$(
  ARCHIVE_JSON="${archive_json}" nix eval --impure --raw --expr '
    let
      archived = builtins.fromJSON (builtins.readFile (builtins.getEnv "ARCHIVE_JSON"));
      labs = archived.inputs."network-labs" or null;
      labsPath = if labs == null then null else labs.path or null;
    in
      if labsPath == null then throw "tests: missing archived network-labs input path" else "${labsPath}/examples"
  '
)"

: >"${violations}"

examples=(
  single-wan-with-nebula
  single-wan-with-nebula-any-to-any-fw
  overlay-east-west
  dual-wan-branch-overlay
  dual-wan-branch-overlay-bgp
  single-wan-any-to-any-fw
  s-router-overlay-dns-lane-policy
)

check_example() {
  local example="$1"
  local example_start_ms
  local output_json

  example_start_ms="$(test_now_ms)"
  output_json="${out_dir}/${example}.json"
  nix run "${repo_root}#compile-and-build-forwarding-model" -- \
    "${examples_root}/${example}/intent.nix" 2>"${out_dir}/${example}.stderr" \
    | jq -c . >"${output_json}" || {
    cat "${out_dir}/${example}.stderr" >&2
    echo "!!!! ${example} failed to compile forwarding model" >&2
    exit 1
  }

  jq -r --arg example "${example}" '
    .enterprise
    | to_entries[] as $enterprise
    | $enterprise.value.site
    | to_entries[] as $site
    | $site.value.nodes
    | to_entries[] as $node
    | select(($node.value.role // "") as $role
        | ["policy", "upstream-selector", "downstream-selector"]
        | index($role))
    | ($node.value.interfaces // {})
    | to_entries[] as $iface
    | ($iface.value.routes.ipv4 // []), ($iface.value.routes.ipv6 // [])
    | .[]?
    | select((.reason // "") == "policy-derived-default")
    | select((.policyOnly // false) != true)
    | "!!!! "
      + $example
      + " "
      + $enterprise.key
      + "."
      + $site.key
      + " node="
      + $node.key
      + " role="
      + ($node.value.role // "<missing>")
      + " interface="
      + $iface.key
      + " route="
      + (.dst // "<missing>")
      + " policy-derived default is not policyOnly"
  ' "${output_json}" >"${out_dir}/${example}.violations"

  pass_timed "lane-default-routes-policy-only:${example}" "${example_start_ms}"
}

pids=()
names=()
logs=()

cleanup_workers() {
  local pid
  for pid in "${pids[@]:-}"; do
    if kill -0 "${pid}" 2>/dev/null; then
      kill "${pid}" 2>/dev/null || true
    fi
  done
}

trap 'cleanup_workers; rm -f "${archive_json}" "${violations}"; rm -rf "${out_dir}"' EXIT INT TERM

running_jobs() {
  local count=0
  local pid
  for pid in "${pids[@]:-}"; do
    if kill -0 "${pid}" 2>/dev/null; then
      count=$((count + 1))
    fi
  done
  printf '%s\n' "${count}"
}

wait_for_slot() {
  while [ "$(running_jobs)" -ge "${max_jobs}" ]; do
    sleep 0.2
  done
}

# !!!! This is intentionally upstream of CPM. Route lane scoping belongs in the
# forwarding model, not in renderers or s-router-test helpers. Add deeper route
# behavior tests next to this when new examples expose unsafe default handling.
for example in "${examples[@]}"; do
  wait_for_slot
  log="${out_dir}/${example}.log"
  check_example "${example}" >"${log}" 2>&1 &
  pids+=("$!")
  names+=("${example}")
  logs+=("${log}")
done

failed=0
for idx in "${!pids[@]}"; do
  pid="${pids[$idx]}"
  name="${names[$idx]}"
  log="${logs[$idx]}"

  if wait "${pid}"; then
    cat "${log}"
  else
    failed=$((failed + 1))
    cat "${log}" >&2
    echo "FAIL lane-default-routes-policy-only:${name}" >&2
  fi
done

if [ "${failed}" -ne 0 ]; then
  exit 1
fi

for example in "${examples[@]}"; do
  cat "${out_dir}/${example}.violations" >>"${violations}"
done

if [[ -s "${violations}" ]]; then
  cat "${violations}" >&2
  exit 1
fi

pass_timed "lane-default-routes-policy-only"
