#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-250-HDS-010-SDS-010-SMS-010
# GAMP-ID: FS-250-HDS-010-SDS-010-SMS-020
# GAMP-SCOPE: software-module-test

repo_root="$(git rev-parse --show-toplevel)"
source "${repo_root}/tests/lib/timing.sh"

start_ms="$(test_now_ms)"
tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

expr_nix="${tmpdir}/fs250-core-role-minimal-authority.nix"
result_json="${tmpdir}/fs250-core-role-minimal-authority.json"

cat >"${expr_nix}" <<'NIX'
let
  repoRoot = builtins.getEnv "REPO_ROOT";
  flake = builtins.getFlake ("path:" + repoRoot);
  lib = flake.inputs.nixpkgs.lib;
  semanticNode = import (repoRoot + "/implementation/s88/Site/topology/semantic-node.nix") {
    inherit lib;
    self = { outPath = repoRoot; };
  };

  baseSite = {
    domains.tenants = [
      { name = "client"; ipv6 = "fd00:250:10::/64"; }
    ];
    ownership.endpoints = [
      { name = "provider-endpoint"; tenant = "client"; }
    ];
    communicationContract = {
      services = [
        { name = "resolver-service"; providers = [ "provider-endpoint" ]; }
      ];
      relations = [ ];
    };
    providerProfiles.unrelated = {
      publicIngress = true;
      recursion = true;
      management = true;
      payload = true;
    };
  };

  temptingCoreNode = {
    role = "core";
    placement = {
      sharedHost = "shared-core-access-host";
      coLocatedRoles = [ "access" "resolver" "management" "public-ingress" ];
    };
    interfaces = {
      wan0 = {
        kind = "wan";
        uplink = "wan";
        routes.ipv4 = [
          {
            dst = "0.0.0.0/0";
            proto = "dhcp";
            source = "route-availability";
          }
        ];
      };
      tenant0 = {
        kind = "tenant";
        tenant = "client";
      };
      mgmt0 = {
        kind = "management";
      };
      resolver0 = {
        kind = "resolver";
      };
    };
    providerProfile = "unrelated";
    services = {
      resolver = { recursive = true; };
      publicIngress = { enabled = true; };
      payload = { enabled = true; };
      management = { enabled = true; };
    };
    routeAvailability = {
      default = true;
      tenant = true;
      service = true;
    };
    uplinks.wan = { };
  };

  buildCore = site: node:
    semanticNode.build {
      nodeName = "core";
      inherit node site;
      role = "core";
      siteUplinkCoreNames = [ "core" ];
      siteUplinkNames = [ "wan" ];
      siteExternalDomains = [ "wan" ];
    };

  pollutedCore = buildCore baseSite temptingCoreNode;

  nat66Site = baseSite // {
    communicationContract = baseSite.communicationContract // {
      relations = [
        {
          id = "allow-client-to-wan";
          action = "allow";
          returnBehavior = "symmetric";
          from = { kind = "tenant"; name = "client"; };
          to = { kind = "external"; name = "wan"; };
        }
      ];
    };
  };
  explicitNat66Core = buildCore nat66Site (temptingCoreNode // {
    uplinks = {
      wan = {
        egress.ipv6.translation.mode = "nat66";
      };
    };
  });

  forbiddenFunctions = [
    "access-gateway"
    "tenant-edge"
    "resolver"
    "recursive-resolver"
    "management"
    "public-ingress"
    "payload"
  ];

  hasForbiddenFunction =
    node:
    builtins.any (name: builtins.elem name (node.forwardingFunctions or [ ])) forbiddenFunctions;

  checks = {
    coreFunctionsMinimal =
      pollutedCore.forwardingFunctions == [
        "router-identity"
        "transit-forwarder"
        "external-egress"
        "uplink-anchor"
      ];
    coreResponsibilityMinimal =
      pollutedCore.forwardingResponsibility == {
        anchorsExternalUplinks = true;
        carriesTransit = true;
        enforcesPolicy = false;
        explicit = true;
        participatesInUpstreamSelection = true;
        terminatesOverlays = false;
        terminatesTenants = false;
      };
    coreRoutingAuthorityMinimal =
      pollutedCore.routingAuthority == {
        connectedReachability = true;
        defaultReachability = false;
        exitsSite = true;
        explicit = true;
        internalReachability = true;
        overlayReachability = false;
        selectsUpstream = false;
        uplinkLearnedReachability = false;
      };
    coreTraversalMinimal =
      pollutedCore.traversalParticipation == {
        enforcement = false;
        exit = true;
        explicit = true;
        ingress = false;
        participates = true;
        transit = true;
        upstreamSelection = false;
      };
    noUnrelatedFunctionAuthority = !(hasForbiddenFunction pollutedCore);
    coLocationDidNotTerminateTenants = pollutedCore.forwardingResponsibility.terminatesTenants == false;
    routeAvailabilityDidNotCreateDefault = pollutedCore.routingAuthority.defaultReachability == false;
    providerProfileDidNotCreateResolverOrIngress = !(hasForbiddenFunction pollutedCore);
    noNat66WithoutExplicitTranslation = pollutedCore.egressIntent.nat66 == { };
    explicitNat66UsesModeledTenantSource =
      explicitNat66Core.egressIntent.nat66.wan == {
        mode = "nat66";
        sourcePrefixes = [ "fd00:250:10::/64" ];
      };
  };
in
{
  inherit pollutedCore explicitNat66Core checks;
}
NIX

REPO_ROOT="${repo_root}" nix eval \
  --extra-experimental-features 'nix-command flakes' \
  --impure --json --file "${expr_nix}" >"${result_json}"

failed_checks="$(jq -r '.checks | to_entries[] | select(.value != true) | .key' "${result_json}")"
if [[ -n "${failed_checks}" ]]; then
  echo "FAIL fs250-core-role-minimal-authority" >&2
  echo "failed checks:" >&2
  while IFS= read -r failed_check; do
    echo "  ${failed_check}" >&2
  done <<<"${failed_checks}"
  jq '.' "${result_json}" >&2
  exit 1
fi

echo "PASS fs250-core-role-minimal-authority"
pass_timed "fs250-core-role-minimal-authority" "${start_ms}"
