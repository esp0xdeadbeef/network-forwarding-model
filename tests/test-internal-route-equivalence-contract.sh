#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: SMT-NFM-FS940-ROUTE-EQUIVALENCE-001
# GAMP-SCOPE: software-module-test

repo_root="$(git rev-parse --show-toplevel)"
source "${repo_root}/tests/lib/timing.sh"

archive_json="$(mktemp)"
tmpdir="$(mktemp -d)"
trap 'rm -f "${archive_json}"; rm -rf "${tmpdir}"' EXIT

nix flake archive --json "path:${repo_root}" >"${archive_json}"
labs_root="$(jq -er '.inputs["network-labs"].path' "${archive_json}")"

examples=(
  s-router-overlay-dns-lane-policy
  tri-site-dual-wan-overlay-integration-static
  tri-site-s-router-overlay-egress
)

for example in "${examples[@]}"; do
  intent="${labs_root}/examples/${example}/intent.nix"
  output_json="${tmpdir}/${example}.json"

  start_ms="$(test_now_ms)"
  nix run "${repo_root}#compile-and-build-forwarding-model" -- "${intent}" >"${output_json}"
  pass_timed "internal-route-equivalence-contract:${example}:compile" "${start_ms}"

  jq -e '
    def routes:
      .enterprise[]?.site[]?.nodes[]?.interfaces[]?.routes? as $routes
      | ($routes.ipv4[]? | . + { family: 4 }),
        ($routes.ipv6[]? | . + { family: 6 });

    def is_default:
      (.dst // "") == "0.0.0.0/0" or (.dst // "") == "::/0";

    . as $root
    | ([
        $root | routes
        | select((.sourceFile // null) != null and (.dst // null) != null)
      ] | length == 0)
    and
    ([
        $root | routes
        | select((.sourceFile // null) != null)
        | select(
            (.family != 6)
            or ((.via6 // null) == null)
            or ((.intent.kind // "") != "runtime-routed-prefix-return")
          )
      ] | length == 0)
    and
    ([
        $root | routes
        | select((.intent.kind // "") == "internal-reachability")
        | select((.dst // null) != null)
        | select(
            (.family == 4 and ((.via4 // null) == null or (.via6 // null) != null))
            or
            (.family == 6 and ((.via6 // null) == null or (.via4 // null) != null))
          )
      ] | length == 0)
    and
    ([
        $root | routes
        | select((.intent.kind // "") == "internal-reachability")
        | select(is_default)
      ] | length == 0)
  ' "${output_json}" >/dev/null || {
    echo "FAIL internal-route-equivalence-contract ${example}: route semantic invariant failed" >&2
    jq '
      def routes:
        .enterprise[]?.site[]?.nodes[]?.interfaces[]?.routes? as $routes
        | ($routes.ipv4[]? | . + { family: 4 }),
          ($routes.ipv6[]? | . + { family: 6 });
      [
        routes
        | select(
            ((.sourceFile // null) != null and (.dst // null) != null)
            or
            ((.sourceFile // null) != null and (
              (.family != 6)
              or ((.via6 // null) == null)
              or ((.intent.kind // "") != "runtime-routed-prefix-return")
            ))
            or
            ((.intent.kind // "") == "internal-reachability" and (.dst // null) != null and (
              (.family == 4 and ((.via4 // null) == null or (.via6 // null) != null))
              or
              (.family == 6 and ((.via6 // null) == null or (.via4 // null) != null))
              or
              ((.dst // "") == "0.0.0.0/0" or (.dst // "") == "::/0")
            ))
          )
      ][0:20]
    ' "${output_json}" >&2
    exit 1
  }
done

pass_timed "internal-route-equivalence-contract"
