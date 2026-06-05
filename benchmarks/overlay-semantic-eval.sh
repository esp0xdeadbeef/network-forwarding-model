#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

threshold_ms="${NFM_BENCH_THRESHOLD_MS:-3000}"
if ! [[ "${threshold_ms}" =~ ^[0-9]+$ ]] || [ "${threshold_ms}" -lt 1 ]; then
  echo "FAIL overlay-semantic-eval: NFM_BENCH_THRESHOLD_MS must be a positive integer" >&2
  exit 1
fi

repo_revision="$(git -C "${repo_root}" rev-parse HEAD 2>/dev/null || echo unknown)"
repo_dirty=false
if ! git -C "${repo_root}" diff --quiet >/dev/null 2>&1 || ! git -C "${repo_root}" diff --cached --quiet >/dev/null 2>&1; then
  repo_dirty=true
fi
locked_revisions="$(jq -r '[.nodes | to_entries[] | select(.value.locked.rev?) | "\(.key)=\(.value.locked.rev)"] | join(",")' "${repo_root}/flake.lock")"
host_class="$(uname -m)-$(uname -s | tr '[:upper:]' '[:lower:]')"
excluded_runtime_stages="nix-build,container-image-build,vm-deployment,containerlab-deployment,boot,live-packet-validation,provider-calls,cache-misses"

archive_json="$(mktemp)"
trap 'rm -f "${archive_json}"' EXIT

nix flake archive --json "path:${repo_root}" >"${archive_json}"
labs_root="$(jq -er '.inputs["network-labs"].path' "${archive_json}")"

examples=(
  s-router-overlay-dns-lane-policy
  tri-site-dual-wan-overlay-integration-static
  tri-site-s-router-overlay-egress
)

failed=0

for example in "${examples[@]}"; do
  intent="${labs_root}/examples/${example}/intent.nix"
  [[ -f "${intent}" ]] || {
    echo "FAIL overlay-semantic-eval ${example}: missing ${intent}" >&2
    failed=1
    continue
  }

  # Use precomputed compiler JSON so elapsed_ms measures only NFM semantic eval.
  compiled_json="$(mktemp)"
  if ! nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure \
    --json \
    --expr "
      let
        compiler = builtins.getFlake \"github:esp0xdeadbeef/network-compiler\";
        input = import \"${intent}\";
      in
        compiler.libBySystem.x86_64-linux.compile input
    " >"${compiled_json}"; then
    echo "FAIL overlay-semantic-eval ${example}: compiler provider output failed" >&2
    rm -f "${compiled_json}"
    failed=1
    continue
  fi

  start_ms="$(date +%s%3N)"
  summary="$(
    timeout "$((threshold_ms / 1000 + 20))" \
      nix eval \
        --extra-experimental-features 'nix-command flakes' \
        --impure \
        --json \
        --expr "
          let
            flake = builtins.getFlake \"path:${repo_root}\";
            compiled = builtins.fromJSON (builtins.readFile \"${compiled_json}\");
            out = flake.libBySystem.x86_64-linux.buildFromCompilerInputs { input = compiled; };

            compilerSiteMetrics =
              builtins.concatMap
	                (
	                  enterpriseName:
	                  map
	                    (
	                      siteName:
	                      let
	                        enterpriseSites = builtins.getAttr enterpriseName (compiled.sites or { });
	                        site = builtins.getAttr siteName enterpriseSites;
	                      in
	                      {
	                        site = \"\${enterpriseName}.\${siteName}\";
                        tenants = builtins.length (site.tenants or [ ]);
                        services = builtins.length (site.services or [ ]);
                        relations = builtins.length (site.relations or [ ]);
                        trafficPaths = builtins.length (site.trafficPaths or [ ]);
                        overlayAttachments = builtins.length (builtins.attrNames (site.overlayAttachments or { }));
	                      }
	                    )
		                    (builtins.attrNames (builtins.getAttr enterpriseName (compiled.sites or { })))
	                )
                (builtins.attrNames (compiled.sites or { }));

            nfmSiteMetrics =
              builtins.concatMap
	                (
	                  enterpriseName:
	                  map
	                    (
	                      siteName:
	                      let
	                        enterprise = builtins.getAttr enterpriseName (out.enterprise or { });
	                        site = builtins.getAttr siteName (enterprise.site or { });
	                        nodes = site.nodes or { };
                        routeCount =
                          builtins.foldl'
                            (
                              nodeAcc: node:
                              nodeAcc
                              + builtins.foldl'
                                (
                                  ifaceAcc: iface:
                                  ifaceAcc
                                  + builtins.length ((iface.routes or { }).ipv4 or [ ])
                                  + builtins.length ((iface.routes or { }).ipv6 or [ ])
                                )
                                0
                                (builtins.attrValues (node.interfaces or { }))
                            )
                            0
                            (builtins.attrValues nodes);
                      in
                      {
                        site = \"\${enterpriseName}.\${siteName}\";
                        nodes = builtins.length (builtins.attrNames nodes);
                        interfaces =
                          builtins.foldl'
                            (acc: node: acc + builtins.length (builtins.attrNames (node.interfaces or { })))
                            0
                            (builtins.attrValues nodes);
                        routes = routeCount;
	                      }
	                    )
		                    (builtins.attrNames ((builtins.getAttr enterpriseName (out.enterprise or { })).site or { }))
	                )
                (builtins.attrNames (out.enterprise or { }));
          in
          {
            compilerSites = compilerSiteMetrics;
            nfmSites = nfmSiteMetrics;
          }
        "
  )"
  rc=$?
  end_ms="$(date +%s%3N)"
  elapsed_ms=$((end_ms - start_ms))
  rm -f "${compiled_json}"

  if [[ "${rc}" -ne 0 ]]; then
    echo "BENCH overlay-semantic-eval stage=network-forwarding-model example=${example} status=FAIL elapsed_ms=${elapsed_ms} threshold_ms=${threshold_ms} repo_revision=${repo_revision} repo_dirty=${repo_dirty} locked_revisions=${locked_revisions} timing_method=date_ms host_class=${host_class} cache_state=warm-required command=nix-eval-buildFromCompilerInputs upstream_cardinality=unknown downstream_cardinality=unknown excluded_runtime_stages=${excluded_runtime_stages}" >&2
    echo "FAIL overlay-semantic-eval ${example}: evaluation failed after ${elapsed_ms}ms" >&2
    failed=1
    continue
  fi

  max_routes="$(jq '[.nfmSites[].routes] | max // 0' <<<"${summary}")"
  max_relations="$(jq '[.compilerSites[].relations] | max // 0' <<<"${summary}")"
  max_paths="$(jq '[.compilerSites[].trafficPaths] | max // 0' <<<"${summary}")"
  status=PASS
  if [ "${elapsed_ms}" -gt "${threshold_ms}" ]; then
    status=FAIL
  fi
  printf 'BENCH overlay-semantic-eval stage=network-forwarding-model example=%s status=%s elapsed_ms=%s threshold_ms=%s repo_revision=%s repo_dirty=%s locked_revisions=%s timing_method=date_ms host_class=%s cache_state=warm-required command=nix-eval-buildFromCompilerInputs upstream_cardinality=max_relations:%s,max_paths:%s downstream_cardinality=max_routes:%s excluded_runtime_stages=%s max_relations=%s max_paths=%s max_routes=%s\n' \
    "${example}" "${status}" "${elapsed_ms}" "${threshold_ms}" "${repo_revision}" "${repo_dirty}" "${locked_revisions}" "${host_class}" "${max_relations}" "${max_paths}" "${max_routes}" "${excluded_runtime_stages}" "${max_relations}" "${max_paths}" "${max_routes}"

  if [ "${elapsed_ms}" -gt "${threshold_ms}" ]; then
    echo "FAIL overlay-semantic-eval ${example}: ${elapsed_ms}ms exceeds ${threshold_ms}ms" >&2
    failed=1
  fi
done

exit "${failed}"
