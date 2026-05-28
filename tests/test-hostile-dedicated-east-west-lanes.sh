#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: SMT-NFM-HOSTILE-LANE-001
# GAMP-SCOPE: software-module-test

repo_root="$(git rev-parse --show-toplevel)"
source "${repo_root}/tests/lib/timing.sh"

archive_json="$(mktemp)"
output_json="$(mktemp)"
trap 'rm -f "'"${archive_json}"'" "'"${output_json}"'"' EXIT

nix flake archive --json "path:${repo_root}" >"${archive_json}"

labs_path="$(
  ARCHIVE_JSON="${archive_json}" nix eval --impure --raw --expr '
    let
      archived = builtins.fromJSON (builtins.readFile (builtins.getEnv "ARCHIVE_JSON"));
      labs = archived.inputs."network-labs" or null;
      labsPath = if labs == null then null else labs.path or null;
    in
      if labsPath == null then
        throw "tests: missing archived network-labs input path"
      else
        labsPath
  '
)"

intent_path="${labs_path}/examples/s-router-overlay-dns-lane-policy/intent.nix"
nix run "${repo_root}#compile-and-build-forwarding-model" -- "${intent_path}" >"${output_json}"

OUTPUT_JSON="${output_json}" nix eval --impure --expr '
  let
    data = builtins.fromJSON (builtins.readFile (builtins.getEnv "OUTPUT_JSON"));
    siteB = data.enterprise.espbranch.site."site-b";
    links = siteB.links or { };
    trafficPaths = siteB.trafficPaths or [ ];

    hasLink = name: predicate:
      links ? ${name} && predicate links.${name};

    hostileEastWestLane =
      "p2p-b-router-policy-b-router-upstream-selector--access-b-router-access-hostile--uplink-east-west";
    hostileWanLane =
      "p2p-b-router-policy-b-router-upstream-selector--access-b-router-access-hostile--uplink-wan";
    hostilePolicyLane =
      "p2p-b-router-downstream-selector-b-router-policy--access-b-router-access-hostile";
    nebulaCoreLane =
      "p2p-b-router-core-nebula-b-router-upstream-selector";

    hasHostileEastWestPath = builtins.any (
      path:
        (path.relationId or null) == "allow-hostile-to-east-west"
        && (path.stagePath or [ ]) == [
          "access"
          "downstream-selector"
          "policy"
          "upstream-selector"
          "core"
        ]
        && (path.nodePath or [ ]) == [
          "b-router-access-hostile"
          "b-router-downstream-selector"
          "b-router-policy"
          "b-router-upstream-selector"
          "b-router-core-nebula"
        ]
        && (path.corePathNodes or [ ]) == [ "b-router-core-nebula" ]
        && (path.p2pIsolationKey or null) == "allow-hostile-to-east-west"
        && (path.forbidsCoreToCoreP2P or false)
    ) trafficPaths;
  in
    hasHostileEastWestPath
    && hasLink "${hostilePolicyLane}" (
      link:
        (link.kind or null) == "p2p"
        && (link.lane or null) == "access::b-router-access-hostile"
        && (link.laneMeta.access or null) == "b-router-access-hostile"
        && (link.laneMeta.kind or null) == "access"
    )
    && hasLink "${hostileEastWestLane}" (
      link:
        (link.kind or null) == "p2p"
        && (link.lane or null)
          == "access::b-router-access-hostile::uplink::east-west"
        && (link.laneMeta.access or null) == "b-router-access-hostile"
        && (link.laneMeta.kind or null) == "access-uplink"
        && (link.laneMeta.uplink or null) == "east-west"
        && (link.members or [ ]) == [
          "b-router-policy"
          "b-router-upstream-selector"
        ]
    )
    && !(links ? ${hostileWanLane})
    && hasLink "${nebulaCoreLane}" (
      link:
        (link.kind or null) == "p2p"
        && (link.lane or null) == "uplink::east-west"
        && (link.laneMeta.uplink or null) == "east-west"
        && (link.members or [ ]) == [
          "b-router-core-nebula"
          "b-router-upstream-selector"
        ]
    )
' | {
  if ! grep -qx true; then
    echo "FAIL hostile-dedicated-east-west-lanes: hostile traffic must have a dedicated east-west policy lane and no hostile WAN lane" >&2
    exit 1
  fi
}

pass_timed "hostile-dedicated-east-west-lanes"
