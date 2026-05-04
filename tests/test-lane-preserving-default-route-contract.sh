#!/usr/bin/env bash
set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
fixture_dir="${repo_root}/fixtures/passing/lane-preserving-default-routes"
input_path="${fixture_dir}/input.nix"
expected_path="${fixture_dir}/expected-lane-defaults.json"

if [[ ! -f "${input_path}" || ! -f "${expected_path}" ]]; then
  cat >&2 <<EOF
FATAL network-forwarding-model lane-preserving default-route contract is not implemented yet.

missing fixture:
  - ${input_path}
  - ${expected_path}

Regression this prevents:
  DNS looked healthy on paper but live packets from site-a mgmt reached policy
  on the streaming lane. A single downstream-selector default route had
  collapsed multiple access lanes into one policy lane.

Required fixture:
  - at least three access classes: mgmt, client, streaming
  - each access class has a policy-derived default route
  - mgmt DNS must use the mgmt lane
  - client DNS must not use the streaming lane
  - streaming deny rules must not receive mgmt/client DNS packets
  - every default route carries explicit lane metadata:
      access = <access unit>
      uplink = <uplink or overlay domain>
      reason = "policy-derived-default"

Expected JSON shape:
  {
    "enterprise": "acme",
    "site": "ams",
    "routes": [
      {
        "node": "downstream-selector",
        "interface": "p2p-downstream-policy--access-mgmt",
        "family": 4,
        "destination": "0.0.0.0/0",
        "access": "mgmt",
        "uplink": "wan",
        "mustNotShareWith": ["streaming"]
      }
    ]
  }

Fix location:
  Implement this in network-forwarding-model lane/default-route derivation.
  Do not fix it in CPM, NixOS, Containerlab, or local s-router-test scripts.
EOF
  exit 1
fi

tmp_json="$(mktemp)"
ir_json="$(mktemp)"
trap 'rm -f "${tmp_json}" "${ir_json}"' EXIT

nix eval --json --impure --expr "import ${input_path}" >"${ir_json}"
nix run "${repo_root}#debug" -- "${ir_json}" >"${tmp_json}"

OUTPUT_JSON="${tmp_json}" EXPECTED_JSON="${expected_path}" nix eval --impure --expr '
  let
    data = builtins.fromJSON (builtins.readFile (builtins.getEnv "OUTPUT_JSON"));
    expected = builtins.fromJSON (builtins.readFile (builtins.getEnv "EXPECTED_JSON"));
    site = data.enterprise.${expected.enterprise}.site.${expected.site};
    ifaceRoutes = nodeName: ifName:
      (((site.nodes.${nodeName}.interfaces or {}).${ifName} or {}).routes or {});
    routeExists = spec:
      let routes = if spec.family == 6 then (ifaceRoutes spec.node spec.interface).ipv6 or [ ] else (ifaceRoutes spec.node spec.interface).ipv4 or [ ];
      in builtins.any
        (route:
          (route.dst or null) == spec.destination
          && (route.lane.access or null) == spec.access
          && (route.lane.uplink or null) == spec.uplink
          && (route.reason or null) == "policy-derived-default")
        routes;
    noForbiddenSharing = spec:
      let routes = ((ifaceRoutes spec.node spec.interface).ipv4 or [ ]) ++ ((ifaceRoutes spec.node spec.interface).ipv6 or [ ]);
      in builtins.all
        (forbiddenAccess:
          builtins.all (route: (route.lane.access or null) != forbiddenAccess) routes)
        (spec.mustNotShareWith or [ ]);
  in
    builtins.all (spec: routeExists spec && noForbiddenSharing spec) expected.routes
' >/dev/null || {
  cat >&2 <<'EOF'
FAIL lane-preserving-default-route-contract

FWM output did not match expected lane-specific defaults. Each default route must
carry lane metadata and stay scoped to the access/uplink policy lane that caused
it. Smaller-model hint: inspect expected-lane-defaults.json, then implement the
missing lane metadata/route placement in FWM route derivation.
EOF
  exit 1
}

echo "PASS lane-preserving-default-route-contract"
