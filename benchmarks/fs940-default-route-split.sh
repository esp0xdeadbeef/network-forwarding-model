#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

threshold_ms="${NFM_BENCH_THRESHOLD_MS:-3000}"
if ! [[ "${threshold_ms}" =~ ^[0-9]+$ ]] || [ "${threshold_ms}" -lt 1 ]; then
  echo "FAIL fs940-default-route-split: NFM_BENCH_THRESHOLD_MS must be a positive integer" >&2
  exit 1
fi

example="${NFM_FS940_PROFILE_EXAMPLE:-s-router-overlay-dns-lane-policy}"
archive_json="$(mktemp)"
compiler_json="$(mktemp --suffix=.json)"
expr_nix="$(mktemp)"
trap 'rm -f "${archive_json}" "${compiler_json}" "${expr_nix}"' EXIT

nix flake archive --json "path:${repo_root}" >"${archive_json}"
labs_root="$(jq -er '.inputs["network-labs"].path' "${archive_json}")"
intent="${labs_root}/examples/${example}/intent.nix"

if [[ ! -f "${intent}" ]]; then
  echo "FAIL fs940-default-route-split ${example}: missing ${intent}" >&2
  exit 1
fi

nix eval \
  --extra-experimental-features 'nix-command flakes' \
  --impure \
  --json \
  --expr "
    let
      compiler = builtins.getFlake \"github:esp0xdeadbeef/network-compiler\";
      input = import \"${intent}\";
    in
      compiler.libBySystem.x86_64-linux.compile input
  " >"${compiler_json}"

cat >"${expr_nix}" <<'NIX'
let
  nfm = builtins.getFlake (builtins.getEnv "REPO_FLAKE");
  out = nfm.libBySystem.x86_64-linux.buildFromCompilerInputPath (builtins.getEnv "COMPILER_JSON");
  routeCount =
    builtins.foldl'
      (
        enterpriseAcc: enterprise:
        enterpriseAcc
        + builtins.foldl'
          (
            siteAcc: site:
            siteAcc
            + builtins.foldl'
              (
                nodeAcc: node:
                nodeAcc
                + builtins.foldl'
                  (
                    ifaceAcc: iface:
                    let routes = iface.routes or { }; in
                    ifaceAcc + builtins.length (routes.ipv4 or [ ]) + builtins.length (routes.ipv6 or [ ])
                  )
                  0
                  (builtins.attrValues (node.interfaces or { }))
              )
              0
              (builtins.attrValues (site.nodes or { }))
          )
          0
          (builtins.attrValues (enterprise.site or { }))
      )
      0
      (builtins.attrValues (out.enterprise or { }));
in
{
  routes = routeCount;
}
NIX

eval_variant() {
  local variant="$1"
  shift
  local start_ms end_ms elapsed_ms summary max_routes
  start_ms="$(date +%s%3N)"
  if ! summary="$(
    env "$@" REPO_FLAKE="path:${repo_root}" COMPILER_JSON="${compiler_json}" \
      nix eval \
        --extra-experimental-features 'nix-command flakes' \
        --impure \
        --json \
        --file "${expr_nix}"
  )"; then
    echo "FAIL fs940-default-route-split ${example}: ${variant} evaluation failed" >&2
    return 1
  fi
  end_ms="$(date +%s%3N)"
  elapsed_ms="$((end_ms - start_ms))"
  max_routes="$(jq -r '.routes' <<<"${summary}")"
  printf 'BENCH fs940-default-route-split example=%s variant=%s elapsed_ms=%s threshold_ms=%s routes=%s\n' \
    "${example}" "${variant}" "${elapsed_ms}" "${threshold_ms}" "${max_routes}"
  if [[ "${variant}" == "nearest-default-only" || "${variant}" == "policy-lane-default-only" ]]; then
    if [ "${elapsed_ms}" -gt "${threshold_ms}" ]; then
      echo "FAIL fs940-default-route-split ${example}: ${variant} ${elapsed_ms}ms exceeds ${threshold_ms}ms" >&2
      return 1
    fi
  fi
}

failed=0

eval_variant nearest-default-only \
  S88_NFM_PROFILE_SKIP_LANE_DEFAULTS=1 \
  S88_NFM_PROFILE_SKIP_EXTERNAL_INGRESS_DEFAULTS=1 \
  S88_NFM_PROFILE_SKIP_DIRECT_WAN_DEFAULTS=1 \
  S88_NFM_PROFILE_SKIP_UPLINK_LEARNED=1 || failed=1

eval_variant policy-lane-default-only \
  S88_NFM_PROFILE_SKIP_NEAREST_DEFAULTS=1 \
  S88_NFM_PROFILE_SKIP_EXTERNAL_INGRESS_DEFAULTS=1 \
  S88_NFM_PROFILE_SKIP_DIRECT_WAN_DEFAULTS=1 \
  S88_NFM_PROFILE_SKIP_UPLINK_LEARNED=1 || failed=1

eval_variant external-ingress-only \
  S88_NFM_PROFILE_SKIP_NEAREST_DEFAULTS=1 \
  S88_NFM_PROFILE_SKIP_LANE_DEFAULTS=1 \
  S88_NFM_PROFILE_SKIP_DIRECT_WAN_DEFAULTS=1 \
  S88_NFM_PROFILE_SKIP_UPLINK_LEARNED=1 || failed=1

eval_variant direct-wan-only \
  S88_NFM_PROFILE_SKIP_NEAREST_DEFAULTS=1 \
  S88_NFM_PROFILE_SKIP_LANE_DEFAULTS=1 \
  S88_NFM_PROFILE_SKIP_EXTERNAL_INGRESS_DEFAULTS=1 \
  S88_NFM_PROFILE_SKIP_UPLINK_LEARNED=1 || failed=1

eval_variant uplink-learned-only \
  S88_NFM_PROFILE_SKIP_NEAREST_DEFAULTS=1 \
  S88_NFM_PROFILE_SKIP_LANE_DEFAULTS=1 \
  S88_NFM_PROFILE_SKIP_EXTERNAL_INGRESS_DEFAULTS=1 \
  S88_NFM_PROFILE_SKIP_DIRECT_WAN_DEFAULTS=1 || failed=1

exit "${failed}"
