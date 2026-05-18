#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
source "${repo_root}/tests/lib/timing.sh"
archive_json="$(mktemp)"
out_dir="$(mktemp -d)"
violations="$(mktemp)"
trap 'rm -f "${archive_json}" "${violations}"; rm -rf "${out_dir}"' EXIT

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

# !!!! This is intentionally upstream of CPM. Route lane scoping belongs in the
# forwarding model, not in renderers or s-router-test helpers. Add deeper route
# behavior tests next to this when new examples expose unsafe default handling.
for example in \
  single-wan-with-nebula \
  single-wan-with-nebula-any-to-any-fw \
  overlay-east-west \
  dual-wan-branch-overlay \
  dual-wan-branch-overlay-bgp \
  single-wan-any-to-any-fw \
  s-router-overlay-dns-lane-policy
do
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
  ' "${output_json}" >>"${violations}"
done

if [[ -s "${violations}" ]]; then
  cat "${violations}" >&2
  exit 1
fi

pass_timed "lane-default-routes-policy-only"
