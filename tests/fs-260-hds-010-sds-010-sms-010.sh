#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-260-HDS-010-SDS-010-SMS-010
# GAMP-ID: SMT-NFM-FS260-DEFAULT-SITE-FABRIC-CHAIN-HANDOFF-001
# GAMP-SCOPE: software-module-test

repo_root="$(git rev-parse --show-toplevel)"
source "${repo_root}/tests/lib/timing.sh"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

start_ms="$(test_now_ms)"
archive_json="${tmp_dir}/archive.json"
input_file="${tmp_dir}/default-chain.nix"
compiler_json="${tmp_dir}/compiler.json"
nfm_json="${tmp_dir}/nfm.json"
compiler_projection="${tmp_dir}/compiler-projection.json"
nfm_projection="${tmp_dir}/nfm-projection.json"

nix flake archive --json "path:${repo_root}" >"${archive_json}"
compiler_path="$(
  ARCHIVE_JSON="${archive_json}" nix eval --impure --raw --expr '
    let
      archived = builtins.fromJSON (builtins.readFile (builtins.getEnv "ARCHIVE_JSON"));
      compilerPath = archived.inputs."network-compiler".path or null;
    in
      if compilerPath == null then throw "fs260 default fabric handoff: missing network-compiler input" else compilerPath
  '
)"

cat >"${input_file}" <<'NIX'
{
  esp0xdeadbeef = {
    "site-a" = {
      pools = {
        p2p.ipv4 = "10.10.0.0/24";
        loopback.ipv4 = "10.19.0.0/24";
      };

      ownership.prefixes = [
        { kind = "tenant"; name = "client"; ipv4 = "10.20.20.0/24"; }
      ];

      communicationContract.relations = [
        {
          id = "allow-client-to-wan";
          priority = 100;
          from = { kind = "tenant"; name = "client"; };
          to = { kind = "external"; uplinks = [ "wan" ]; };
          trafficType = "any";
          action = "allow";
          returnBehavior = "symmetric";
        }
      ];

      topology.nodes = {
        access-client = {
          role = "access";
          attachments = [ { kind = "tenant"; name = "client"; } ];
        };
        downstream.role = "downstream-selector";
        policy.role = "policy";
        upstream.role = "upstream-selector";
        core-wan = {
          role = "core";
          uplinks.wan.ipv4 = [ "0.0.0.0/0" ];
        };
      };

      topology.links = [
        [ "access-client" "downstream" ]
        [ "downstream" "policy" ]
        [ "policy" "upstream" ]
        [ "upstream" "core-wan" ]
      ];
    };
  };
}
NIX

nix run --no-warn-dirty --no-write-lock-file "path:${compiler_path}#compile" -- \
  "${input_file}" >"${compiler_json}"
nix run "${repo_root}#compile-and-build-forwarding-model" -- \
  "${input_file}" >"${nfm_json}"

jq '
  [
    .sites.esp0xdeadbeef."site-a".trafficPaths[]
    | select(.relationId == "allow-client-to-wan")
    | {
        relationId,
        source,
        destination,
        stagePath,
        nodePath,
        nodePathAlternatives,
        corePathNodes,
        requiresPolicy,
        forbidsCoreToCoreP2P,
        p2pIsolationKey
      }
  ]
' "${compiler_json}" >"${compiler_projection}"

jq '
  [
    .enterprise.esp0xdeadbeef.site."site-a".trafficPaths[]
    | select(.relationId == "allow-client-to-wan")
    | {
        relationId,
        source,
        destination,
        stagePath,
        nodePath,
        nodePathAlternatives,
        corePathNodes,
        requiresPolicy,
        forbidsCoreToCoreP2P,
        p2pIsolationKey
      }
  ]
' "${nfm_json}" >"${nfm_projection}"

diff -u "${compiler_projection}" "${nfm_projection}"

jq -e '
  length == 1
  and .[0].stagePath == [
    "access",
    "downstream-selector",
    "policy",
    "upstream-selector",
    "core"
  ]
  and .[0].nodePath == [
    "access-client",
    "downstream",
    "policy",
    "upstream",
    "core-wan"
  ]
  and .[0].nodePathAlternatives == [[
    "access-client",
    "downstream",
    "policy",
    "upstream",
    "core-wan"
  ]]
  and .[0].corePathNodes == [ "core-wan" ]
  and .[0].requiresPolicy == true
  and .[0].forbidsCoreToCoreP2P == true
  and .[0].p2pIsolationKey == "allow-client-to-wan"
' "${nfm_projection}" >/dev/null

pass_timed "fs260-default-site-fabric-chain-handoff" "${start_ms}"
