#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
source "${repo_root}/tests/lib/timing.sh"
expected_sites="${repo_root}/tests/expected/network-labs-sites.tsv"
expected_routes="${repo_root}/tests/expected/network-labs-routes.tsv"

fail() {
  echo "$1" >&2
  exit 1
}

examples_root="$(
  archive_json="$(mktemp)"
  trap 'rm -f "${archive_json}"' RETURN
  nix flake archive --json "path:${repo_root}" > "${archive_json}"
  ARCHIVE_JSON="${archive_json}" nix eval --impure --raw --expr '
    let
      archived = builtins.fromJSON (builtins.readFile (builtins.getEnv "ARCHIVE_JSON"));
      labs = archived.inputs."network-labs" or null;
      labsPath = if labs == null then null else labs.path or null;
    in
      if labsPath == null then
        throw "tests: missing archived network-labs input path"
      else
        "${labsPath}/examples"
  '
)"

[[ -f "${expected_sites}" ]] || fail "FAIL network-labs-output: missing ${expected_sites}"
[[ -f "${expected_routes}" ]] || fail "FAIL network-labs-routes: missing ${expected_routes}"
[[ -d "${examples_root}" ]] || fail "FAIL network-labs-output: missing ${examples_root}"

actual_sites="$(mktemp)"
actual_routes="$(mktemp)"
actual_sites_sorted="$(mktemp)"
expected_sites_sorted="$(mktemp)"
actual_routes_sorted="$(mktemp)"
expected_routes_sorted="$(mktemp)"
tmp_dir="$(mktemp -d)"
trap 'rm -f "${actual_sites}" "${actual_routes}" "${actual_sites_sorted}" "${expected_sites_sorted}" "${actual_routes_sorted}" "${expected_routes_sorted}"; rm -rf "${tmp_dir}"' EXIT

printf 'example\tenterprise\tsite\tnodes\tlinks\ttopologyLinks\ttransitOrder\tuplinks\toverlays\tinterfaces\tipv4Routes\tipv6Routes\n' > "${actual_sites}"
printf 'example\tenterprise\tsite\tipv4Intent\tipv6Intent\tipv4Proto\tipv6Proto\n' > "${actual_routes}"

max_jobs="${TEST_JOBS:-$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN)}"
if ! [[ "${max_jobs}" =~ ^[0-9]+$ ]] || [ "${max_jobs}" -lt 1 ]; then
  max_jobs=1
fi

write_site_summary() {
  local example_name="$1"
  local output_json="$2"

  jq -r --arg example "${example_name}" '
    .enterprise
    | to_entries[] as $enterprise
    | $enterprise.value.site
    | to_entries[]
    | . as $site
    | [
        $example,
        $enterprise.key,
        $site.key,
        ($site.value.nodes | keys | length),
        ($site.value.links | keys | length),
        ($site.value.topology.links | length),
        ($site.value.transit.ordering | length),
        ($site.value.uplinkNames | length),
        ($site.value.overlayReachability // {} | keys | length),
        ([$site.value.nodes[]?.interfaces // {} | keys | length] | add // 0),
        ([$site.value.nodes[]?.interfaces[]?.routes.ipv4 // [] | length] | add // 0),
        ([$site.value.nodes[]?.interfaces[]?.routes.ipv6 // [] | length] | add // 0)
      ] | @tsv
  ' "${output_json}"
}

write_route_summary() {
  local example_name="$1"
  local output_json="$2"

  jq -r --arg example "${example_name}" '
    def counts(values):
      values
      | group_by(.)
      | map(.[0] + "=" + (length | tostring))
      | join(",");

    .enterprise
    | to_entries[] as $enterprise
    | $enterprise.value.site
    | to_entries[] as $site
    | [
        $example,
        $enterprise.key,
        $site.key,
        counts([$site.value.nodes[]?.interfaces[]?.routes.ipv4[]?.intent.kind // empty]),
        counts([$site.value.nodes[]?.interfaces[]?.routes.ipv6[]?.intent.kind // empty]),
        counts([$site.value.nodes[]?.interfaces[]?.routes.ipv4[]?.proto // empty]),
        counts([$site.value.nodes[]?.interfaces[]?.routes.ipv6[]?.proto // empty])
      ] | @tsv
  ' "${output_json}"
}

validate_full_sites() {
  local example_name="$1"
  local output_json="$2"

  jq -e '
    def sites:
      .enterprise
      | to_entries[]
      | .value.site
      | to_entries[]
      | .value;

    (.meta.networkForwardingModel.name == "network-forwarding-model")
    and (.meta.networkForwardingModel.schemaVersion == 9)
    and ((.meta.networkForwardingModel.warningMessages // []) == [])
    and ((.enterprise | type) == "object")
    and ((.enterprise | length) > 0)
    and (([sites] | length) > 0)
    and all(sites;
      ((.nodes | type) == "object")
      and ((.links | type) == "object")
      and ((.nodes | length) > 0)
      and ((.links | length) > 0)
      and (((.topology.links // []) | length) > 0)
      and (((.transit.ordering // []) | length) > 0)
      and (([.nodes[]?.interfaces // {} | keys | length] | add // 0) > 0)
      and (([.nodes[]?.interfaces[]?.routes.ipv4 // [] | length] | add // 0) > 0)
      and (([.nodes[]?.interfaces[]?.routes.ipv6 // [] | length] | add // 0) > 0)
    )
  ' "${output_json}" >/dev/null || fail "FAIL network-labs-output: incomplete output for ${example_name}"
}

validate_routes() {
  local example_name="$1"
  local output_json="$2"

  jq -e '
    def routes:
      .enterprise[]?.site[]?.nodes[]?.interfaces[]?.routes
      | (.ipv4[]?, .ipv6[]?);

    ([routes] | length) > 0
    and all(routes;
      (((.dst // "") != "") or ((.sourceFile // "") != ""))
      and ((.proto // "") != "")
      and (((.intent // {}).kind // "") != "")
    )
  ' "${output_json}" >/dev/null || fail "FAIL network-labs-routes: incomplete route metadata for ${example_name}"

}

validate_contracts() {
  local example_name="$1"
  local output_json="$2"

  jq -e '
    def sites:
      .enterprise[]?.site[]?;
    def nodes:
      sites.nodes | to_entries[] | .value;
    def forbidden_paths:
      [
        paths(scalars)
        | map(tostring)
        | join(".")
        | select(test("(^|\\.)(bridge|vlan|namespace|nixos|renderer|mac|macAddress|device|platform|systemd|nftables|junos|cisco|containers)(\\.|$)"; "i"))
      ];
    def role_ok(node):
      (
        node.role == "access"
        and node.forwardingResponsibility.terminatesTenants == true
        and node.traversalParticipation.ingress == true
      )
      or (
        node.role == "downstream-selector"
        and node.forwardingResponsibility.carriesTransit == true
        and node.traversalParticipation.transit == true
      )
      or (
        node.role == "policy"
        and node.forwardingResponsibility.enforcesPolicy == true
        and node.traversalParticipation.enforcement == true
      )
      or (
        node.role == "upstream-selector"
        and node.forwardingResponsibility.participatesInUpstreamSelection == true
        and node.traversalParticipation.upstreamSelection == true
        and node.routingAuthority.selectsUpstream == true
      )
      or (
        node.role == "core"
        and node.routingAuthority.exitsSite == true
      );

    (forbidden_paths | length) == 0
    and all(sites; .transit.dedicatedLanes == true)
    and all(sites;
      .forwardingSemantics.explicit == true
      and ((.forwardingSemantics.policyNodeName // "") != "")
      and (((.forwardingSemantics.coreNodeNames // []) | length) > 0)
      and (((.forwardingSemantics.traversalParticipantNodeNames // []) | length) > 0)
    )
    and all(nodes; role_ok(.))
  ' "${output_json}" >/dev/null || fail "FAIL network-labs-contracts: ${example_name}"
}

run_example() {
  local intent="$1"
  local example_dir="${intent%/*}"
  local example_name="${example_dir##*/}"
  local example_start_ms
  local work_dir="${tmp_dir}/${example_name}"
  local output_json="${work_dir}/output.jsonc"
  local stderr_log="${work_dir}/stderr.log"
  local site_summary="${work_dir}/sites.tsv"
  local route_summary="${work_dir}/routes.tsv"

  example_start_ms="$(test_now_ms)"
  mkdir -p "${work_dir}"
  nix run "${repo_root}#compile-and-build-forwarding-model" -- "${intent}" 2>"${stderr_log}" | jq -c . > "${output_json}" \
    || {
      echo "--- STDERR (${example_name}) ---" >&2
      cat "${stderr_log}" >&2
      fail "FAIL network-labs-output: ${example_name}"
    }

  validate_full_sites "${example_name}" "${output_json}"
  validate_routes "${example_name}" "${output_json}"
  validate_contracts "${example_name}" "${output_json}"
  write_site_summary "${example_name}" "${output_json}" > "${site_summary}"
  write_route_summary "${example_name}" "${output_json}" > "${route_summary}"
  pass_timed "network-labs-output:${example_name}" "${example_start_ms}"
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

trap 'cleanup_workers; rm -f "${actual_sites}" "${actual_routes}" "${actual_sites_sorted}" "${expected_sites_sorted}" "${actual_routes_sorted}" "${expected_routes_sorted}"; rm -rf "${tmp_dir}"' EXIT INT TERM

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

while read -r intent; do
  example_dir="${intent%/*}"
  example_name="${example_dir##*/}"
  log="${tmp_dir}/${example_name}.log"

  wait_for_slot
  run_example "${intent}" >"${log}" 2>&1 &
  pids+=("$!")
  names+=("${example_name}")
  logs+=("${log}")
done < <(find "${examples_root}" -mindepth 2 -maxdepth 2 -type f -name intent.nix | sort)

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
    echo "FAIL network-labs-output:${name}" >&2
  fi
done

if [ "${failed}" -ne 0 ]; then
  fail "FAIL network-labs-output: ${failed} example(s) failed"
fi

while read -r intent; do
  example_dir="${intent%/*}"
  example_name="${example_dir##*/}"
  cat "${tmp_dir}/${example_name}/sites.tsv" >> "${actual_sites}"
  cat "${tmp_dir}/${example_name}/routes.tsv" >> "${actual_routes}"
done < <(find "${examples_root}" -mindepth 2 -maxdepth 2 -type f -name intent.nix | sort)

{
  head -n 1 "${expected_sites}"
  tail -n +2 "${expected_sites}" | LC_ALL=C sort
} > "${expected_sites_sorted}"

{
  head -n 1 "${actual_sites}"
  tail -n +2 "${actual_sites}" | LC_ALL=C sort
} > "${actual_sites_sorted}"

if ! diff -u "${expected_sites_sorted}" "${actual_sites_sorted}"; then
  fail "FAIL network-labs-output: site summary changed"
fi

pass_timed "network-labs-output"

{
  head -n 1 "${expected_routes}"
  tail -n +2 "${expected_routes}" | LC_ALL=C sort
} > "${expected_routes_sorted}"

{
  head -n 1 "${actual_routes}"
  tail -n +2 "${actual_routes}" | LC_ALL=C sort
} > "${actual_routes_sorted}"

if ! diff -u "${expected_routes_sorted}" "${actual_routes_sorted}"; then
  fail "FAIL network-labs-routes: route summary changed"
fi

pass_timed "network-labs-routes"
pass_timed "network-labs-contracts"
