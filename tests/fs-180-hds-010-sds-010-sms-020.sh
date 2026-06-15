#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-180-HDS-010-SDS-010-SMS-020
# GAMP-ID: SMT-NFM-FS180-ADJACENT-DENIAL-HANDOFF-001
# GAMP-SCOPE: software-module-test

repo_root="$(git rev-parse --show-toplevel)"
source "${repo_root}/tests/lib/timing.sh"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

start_ms="$(test_now_ms)"
archive_json="${tmp_dir}/archive.json"
input_file="${tmp_dir}/adjacent-traffic-denial.nix"
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
      if compilerPath == null then throw "adjacent traffic denial handoff: missing network-compiler input" else compilerPath
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

      ownership = {
        prefixes = [
          { kind = "tenant"; name = "client"; ipv4 = "10.20.10.0/24"; }
          { kind = "tenant"; name = "admin"; ipv4 = "10.20.20.0/24"; }
          { kind = "tenant"; name = "dmz"; ipv4 = "10.20.30.0/24"; }
        ];
        endpoints = [
          { kind = "host"; name = "admin-web-host"; tenant = "admin"; }
          { kind = "host"; name = "dmz-web-host"; tenant = "dmz"; }
        ];
      };

      communicationContract = {
        trafficTypes = [
          { name = "https"; match = [ { proto = "tcp"; family = "any"; dports = [ 443 ]; } ]; }
          { name = "ssh"; match = [ { proto = "tcp"; family = "any"; dports = [ 22 ]; } ]; }
        ];
        services = [
          { name = "admin-web"; providers = [ "admin-web-host" ]; trafficType = "https"; }
          { name = "dmz-web"; providers = [ "dmz-web-host" ]; trafficType = "https"; }
        ];
        relations = [
          {
            id = "allow-client-to-admin-web-https";
            priority = 10;
            from = { kind = "tenant"; name = "client"; };
            to = { kind = "service"; name = "admin-web"; };
            trafficType = "https";
            action = "allow";
          }
          {
            id = "deny-client-to-admin-web-ssh";
            priority = 20;
            from = { kind = "tenant"; name = "client"; };
            to = { kind = "service"; name = "admin-web"; };
            trafficType = "ssh";
            action = "deny";
          }
          {
            id = "deny-admin-to-admin-web-https";
            priority = 30;
            from = { kind = "tenant"; name = "admin"; };
            to = { kind = "service"; name = "admin-web"; };
            trafficType = "https";
            action = "deny";
          }
          {
            id = "deny-client-to-dmz-web-https";
            priority = 40;
            from = { kind = "tenant"; name = "client"; };
            to = { kind = "service"; name = "dmz-web"; };
            trafficType = "https";
            action = "deny";
          }
          {
            id = "allow-client-to-wan";
            priority = 50;
            from = { kind = "tenant"; name = "client"; };
            to = { kind = "external"; uplinks = [ "wan" ]; };
            trafficType = "https";
            action = "allow";
          }
        ];
      };

      topology.nodes = {
        access-client = {
          role = "access";
          attachments = [ { kind = "tenant"; name = "client"; } ];
        };
        access-admin = {
          role = "access";
          attachments = [ { kind = "tenant"; name = "admin"; } ];
        };
        access-dmz = {
          role = "access";
          attachments = [ { kind = "tenant"; name = "dmz"; } ];
        };
        downstream.role = "downstream-selector";
        policy.role = "policy";
        upstream.role = "upstream-selector";
        core = {
          role = "core";
          uplinks.wan.ipv4 = [ "0.0.0.0/0" ];
        };
      };

      topology.links = [
        [ "access-client" "downstream" ]
        [ "access-admin" "downstream" ]
        [ "access-dmz" "downstream" ]
        [ "downstream" "policy" ]
        [ "policy" "upstream" ]
        [ "upstream" "core" ]
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
    | select(.relationId | test("^(allow-client-to-admin-web-https|deny-)"))
    | {
        relationId,
        action,
        trafficType,
        source,
        destination,
        stagePath,
        nodePath
      }
  ] | sort_by(.relationId)
' "${compiler_json}" >"${compiler_projection}"

jq '
  [
    .enterprise.esp0xdeadbeef.site."site-a".trafficPaths[]
    | select(.relationId | test("^(allow-client-to-admin-web-https|deny-)"))
    | {
        relationId,
        action,
        trafficType,
        source,
        destination,
        stagePath,
        nodePath
      }
  ] | sort_by(.relationId)
' "${nfm_json}" >"${nfm_projection}"

diff -u "${compiler_projection}" "${nfm_projection}"

jq -e '
  length == 4
  and ([
    .[]
    | select(.action == "allow")
    | .relationId
  ] == [ "allow-client-to-admin-web-https" ])
  and all(.[] | select(.relationId | startswith("deny-")); .action == "deny")
' "${nfm_projection}" >/dev/null

pass_timed "adjacent-traffic-denial-handoff" "${start_ms}"
