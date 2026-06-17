#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-510-HDS-010-SDS-010-SMS-010
# GAMP-SCOPE: software-module-test
# Focused construction test: destination ownership boundary.
# SMS-010 verifies that model-owned public IPv4 destinations are NOT
# classified as generic WAN, and that destination classification is never
# skipped before path selection.  Seeded negatives are active.

repo_root="$(git rev-parse --show-toplevel)"
source "${repo_root}/tests/lib/timing.sh"
tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

input_nix="${tmpdir}/compiler-output.nix"
output_json="${tmpdir}/out.json"

cat >"${input_nix}" <<'NIX'
{
  sites.acme.ams = {
    addressPools = {
      local.ipv4 = "10.39.0.0/24";
      p2p.ipv4 = "10.39.1.0/24";
      p2p.ipv6 = "fd42:390::/118";
    };

    attachments = [
      { unit = "access-client"; kind = "tenant"; name = "client"; }
    ];

    domains = {
      externals = [ { kind = "external"; name = "wan"; } ];
      tenants = [
        {
          kind = "tenant";
          name = "client";
          ipv4 = "10.39.20.0/24";
          publicIpv4 = "198.51.100.10/32";
        }
      ];
    };

    ownership.endpoints = [
      {
        kind = "local";
        name = "model-owned-endpoint";
        publicIpv4 = "198.51.100.12/32";
      }
    ];

    communicationContract = {
      services = [
        {
          name = "public-web";
          publicIngress = {
            enabled = true;
            ipv4 = "198.51.100.14/32";
          };
        }
      ];
      allowedRelations = [
        {
          id = "allow-client-to-wan";
          priority = 100;
          from = { kind = "tenant"; name = "client"; };
          to = { kind = "external"; uplinks = [ "wan" ]; };
          trafficType = "any";
          action = "allow";
        }
      ];
      relations = [
        {
          id = "allow-client-to-wan";
          priority = 100;
          from = { kind = "tenant"; name = "client"; };
          to = { kind = "external"; uplinks = [ "wan" ]; };
          trafficType = "any";
          action = "allow";
        }
      ];
    };

    trafficPaths = [
      # SEEDED NEGATIVE 1: model-owned enterprise-client destination
      # accessed through broad-WAN without shortcut policy.
      # Must NOT be classified as generic-wan-internet.
      # Must be denied (broadWanDenials) with diagnostic.
      {
        relationId = "broad-wan-to-enterprise-client-public";
        action = "allow";
        source = { kind = "tenant"; name = "client"; };
        destination = { kind = "public-ipv4"; ipv4 = "198.51.100.10"; };
        nodePath = [ "access-client" "downstream" "policy" "upstream" "core-wan" ];
      }
      # SEEDED NEGATIVE 1 (continued): model-owned local endpoint
      # accessed through broad-WAN without shortcut policy.
      # Must NOT be classified as generic-wan-internet.
      # Must be denied (broadWanDenials) with diagnostic.
      {
        relationId = "broad-wan-to-local-owned-public";
        action = "allow";
        source = { kind = "tenant"; name = "client"; };
        destination = { kind = "public-ipv4"; ipv4 = "198.51.100.12"; };
        nodePath = [ "access-client" "downstream" "policy" "upstream" "core-wan" ];
      }
      # SEEDED NEGATIVE 1 (continued): model-owned public-ingress
      # accessed through broad-WAN without shortcut policy.
      # Must NOT be classified as generic-wan-internet.
      # Must be denied (broadWanDenials) with diagnostic.
      {
        relationId = "broad-wan-to-public-ingress";
        action = "allow";
        source = { kind = "tenant"; name = "client"; };
        destination = { kind = "public-ipv4"; ipv4 = "198.51.100.14"; };
        nodePath = [ "access-client" "downstream" "policy" "upstream" "core-wan" ];
      }
      # CONTROL: generic-internet destination → must be classified as
      # generic-wan-internet (modelOwned=false, genericWanInternet=true).
      {
        relationId = "ordinary-public-internet";
        action = "allow";
        source = { kind = "tenant"; name = "client"; };
        destination = { kind = "public-ipv4"; ipv4 = "93.184.216.34"; };
        nodePath = [ "access-client" "downstream" "policy" "upstream" "core-wan" ];
      }
    ];

    transit.ordering = [
      [ "access-client" "downstream" ]
      [ "downstream" "policy" ]
      [ "policy" "upstream" ]
      [ "upstream" "core-wan" ]
    ];

    units = {
      access-client.role = "access";
      downstream.role = "downstream-selector";
      policy.role = "policy";
      upstream.role = "upstream-selector";
      core-wan = {
        role = "core";
        uplinks.wan.ipv4 = [ "0.0.0.0/0" ];
      };
    };
  };
}
NIX

start_ms="$(test_now_ms)"
nix run "${repo_root}#compile-and-build-forwarding-model" -- "${input_nix}" >"${output_json}"
pass_timed "fs-510-hds-010-sds-010-sms-010:compile" "${start_ms}"

# SMS-010: Destination Ownership Boundary
#
# SEEDED NEGATIVE 1: Model-owned public addresses are NOT classified as
# generic-wan-internet.  They keep their model-owned class and must NOT
# carry genericWanInternet=true.
#
# SEEDED NEGATIVE 2: Every trafficPath destination MUST have a corresponding
# destinationClasses entry — classification is never skipped.
#
# BROAD-WAN DENIAL: Model-owned addresses accessed without explicit
# shortcut policy must appear in broadWanDenials with an allowed=false
# record and a diagnostic.

jq -e '
  .enterprise.acme.site.ams.publicIpv4DestinationPolicy as $policy

  # REQUIRED destinationClasses entries
  | $policy.destinationClasses["public-ipv4-destination::198.51.100.10"] as $enterpriseClient
  | $policy.destinationClasses["public-ipv4-destination::198.51.100.12"] as $localOwned
  | $policy.destinationClasses["public-ipv4-destination::198.51.100.14"] as $publicIngress
  | $policy.destinationClasses["public-ipv4-destination::93.184.216.34"] as $genericWan

  # SEEDED NEGATIVE 1: model-owned → NOT genericWanInternet
  | ($enterpriseClient.modelOwned == true)
    and ($enterpriseClient.genericWanInternet != true)
    and ($localOwned.modelOwned == true)
    and ($localOwned.genericWanInternet != true)
    and ($publicIngress.modelOwned == true)
    and ($publicIngress.genericWanInternet != true)

  # CONTROL: generic-internet → IS genericWanInternet, NOT modelOwned
  and ($genericWan.modelOwned == false)
    and ($genericWan.genericWanInternet == true)

  # SEEDED NEGATIVE 2: all three trafficPath destinations with
  # model-owned addresses appear in destinationClasses — classification
  # was not skipped.
  and ($enterpriseClient != null)
    and ($localOwned != null)
    and ($publicIngress != null)
    and ($genericWan != null)

  # BROAD-WAN DENIAL: all three model-owned paths must be denied
  # because they use broad-WAN without explicit shortcut policy.
  and ([ $policy.broadWanDenials[]
        | select(.relationId == "broad-wan-to-enterprise-client-public"
                 and .allowed == false)
      ] | length == 1)

  and ([ $policy.broadWanDenials[]
        | select(.relationId == "broad-wan-to-local-owned-public"
                 and .allowed == false)
      ] | length == 1)

  and ([ $policy.broadWanDenials[]
        | select(.relationId == "broad-wan-to-public-ingress"
                 and .allowed == false)
      ] | length == 1)

  # CONTROL: generic internet → NOT denied
  and ([ $policy.broadWanDenials[]
        | select(.relationId == "ordinary-public-internet")
      ] | length == 0)

  # DIAGNOSTICS: each denied path produces a diagnostic
  and ([ $policy.diagnostics[]
        | select(.relationId != null)
        | .relationId
      ] | sort) == (["broad-wan-to-enterprise-client-public",
                     "broad-wan-to-local-owned-public",
                     "broad-wan-to-public-ingress"] | sort)
' "${output_json}" >/dev/null || {
  echo "FAIL FS-510-HDS-010-SDS-010-SMS-010: destination ownership boundary incorrect" >&2
  jq '.enterprise.acme.site.ams.publicIpv4DestinationPolicy.destinationClasses' "${output_json}" >&2
  jq '.enterprise.acme.site.ams.publicIpv4DestinationPolicy.broadWanDenials' "${output_json}" >&2
  exit 1
}

echo "PASS: FS-510-HDS-010-SDS-010-SMS-010 — destination ownership boundary verified (seeded negatives 1+2, broad-WAN denial)."
pass_timed "fs-510-hds-010-sds-010-sms-010"
