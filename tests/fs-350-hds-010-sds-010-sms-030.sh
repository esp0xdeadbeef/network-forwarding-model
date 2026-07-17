#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-350-HDS-010-SDS-010-SMS-030
# GAMP-SCOPE: software-module-test

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
      local.ipv4 = "10.35.0.0/24";
      p2p.ipv4 = "10.35.1.0/24";
      p2p.ipv6 = "fd42:350:0:1000::/118";
    };

    attachments = [
      { unit = "access-client"; kind = "tenant"; name = "client"; }
    ];

    domains = {
      externals = [ { kind = "external"; name = "east-west"; } ];
      tenants = [
        {
          kind = "tenant";
          name = "client";
          ipv4 = "10.35.20.0/24";
          ipv6 = "fd42:350:20::/64";
        }
      ];
    };

    communicationContract.relations = [
      {
        id = "allow-client-to-overlay";
        priority = 100;
        from = { kind = "tenant"; name = "client"; };
        to = { kind = "external"; name = "east-west"; };
        trafficType = "any";
        action = "allow";
        returnBehavior = "symmetric";
      }
    ];

    transit.ordering = [
      [ "access-client" "downstream" ]
      [ "downstream" "policy" ]
      [ "policy" "upstream" ]
      [ "upstream" "core-overlay" ]
    ];

    transport.overlays = [
      {
        name = "east-west";
        peerSite = "acme.branch";
        terminateOn = "core-overlay";
      }
    ];

    units = {
      access-client.role = "access";
      downstream.role = "downstream-selector";
      policy.role = "policy";
      upstream.role = "upstream-selector";
      core-overlay = {
        role = "core";
        uplinks.east-west.ipv4 = [ "100.96.35.0/24" ];
        uplinks.east-west.ipv6 = [ "fd42:350:96::/64" ];
      };
    };
  };

  sites.acme.branch = {
    addressPools = {
      local.ipv4 = "10.45.0.0/24";
      p2p.ipv4 = "10.45.1.0/24";
      p2p.ipv6 = "fd42:450:0:1000::/118";
    };

    attachments = [
      { unit = "access-remote"; kind = "tenant"; name = "remote-client"; }
    ];

    domains = {
      externals = [ { kind = "external"; name = "east-west"; } ];
      tenants = [
        {
          kind = "tenant";
          name = "remote-client";
          ipv4 = "10.45.40.0/24";
          ipv6 = "fd42:450:40::/64";
          routedPrefixes = [
            {
              allocation = "runtime";
              family = "ipv6";
              name = "remote-client-host-only";
              delegatedPrefixLength = 128;
              perTenantPrefixLength = 128;
              slot = 0;
              sourceFile = "/run/pd/remote-client-host-only.prefix";
            }
          ];
        }
      ];
    };

    communicationContract.relations = [
      {
        id = "allow-remote-client-to-overlay";
        priority = 100;
        from = { kind = "tenant"; name = "remote-client"; };
        to = { kind = "external"; name = "east-west"; };
        trafficType = "any";
        action = "allow";
        returnBehavior = "symmetric";
      }
    ];

    transit.ordering = [
      [ "access-remote" "downstream-remote" ]
      [ "downstream-remote" "policy-remote" ]
      [ "policy-remote" "upstream-remote" ]
      [ "upstream-remote" "core-remote" ]
    ];

    transport.overlays = [
      {
        name = "east-west";
        peerSite = "acme.ams";
        terminateOn = "core-remote";
      }
    ];

    units = {
      access-remote.role = "access";
      downstream-remote.role = "downstream-selector";
      policy-remote.role = "policy";
      upstream-remote.role = "upstream-selector";
      core-remote = {
        role = "core";
        uplinks.east-west.ipv4 = [ "100.96.45.0/24" ];
        uplinks.east-west.ipv6 = [ "fd42:450:96::/64" ];
      };
    };
  };
}
NIX

start_ms="$(test_now_ms)"
nix run "${repo_root}#compile-and-build-forwarding-model" -- "${input_nix}" >"${output_json}"
pass_timed "fs350-overlay-ledger-construction:compile" "${start_ms}"

jq -e '
  .enterprise.acme.site.branch as $remote
  | .enterprise.acme.site.ams as $local
  | ($remote.tenantPrefixOwners | to_entries | map(.value) | map(select((.dst // null) == "10.45.40.0/24")) | first) as $remoteV4Owner
  | ($remote.tenantPrefixOwners | to_entries | map(.value) | map(select((.family // null) == 6 and (.netName // null) == "remote-client" and (.dst // null) != null)) | first) as $remoteV6Owner
  | ($remote.tenantPrefixOwners | to_entries | map(.value) | map(select((.sourceFile // null) == "/run/pd/remote-client-host-only.prefix")) | first) as $hostOnlyOwner
  | ($remote.prefixAuthority.records | to_entries | map(.value) | map(select((.prefix // null) == "10.45.40.0/24")) | first) as $remoteV4Authority
  | ($remote.prefixAuthority.records | to_entries | map(.value) | map(select((.family // null) == 6 and (.netName // null) == "remote-client" and (.prefix // null) != null)) | first) as $remoteV6Authority
  | ($remote.prefixAuthority.records | to_entries | map(.value) | map(select((.sourceFile // null) == "/run/pd/remote-client-host-only.prefix")) | first) as $hostOnlyAuthority
  | def local_overlay_routes:
      [
        $local.nodes
        | to_entries[]
        | . as $node
        | ($node.value.interfaces // {})
        | to_entries[]
        | (.value.routes.ipv4[]?, .value.routes.ipv6[]?)
        | { node: $node.key, route: . }
        | select(
            (.route.intent.kind // null) == "overlay-reachability"
            and (.route.overlay // null) == "east-west"
            and (.route.peerSite // null) == "acme.branch"
          )
      ];
  ($remoteV4Owner.owner == "access-remote")
  and ($remoteV4Owner.netName == "remote-client")
  and ($remoteV6Owner.owner == "access-remote")
  and ($remoteV6Owner.netName == "remote-client")
  and ($hostOnlyOwner.owner == "access-remote")
  and ($hostOnlyOwner.authorityClass == "host-only-provider-prefix")
  and ($remoteV4Authority.authorityClass == "access-subnet-pool")
  and ($remoteV4Authority.childPurpose == "tenant-or-access-assignment")
  and ($remoteV6Authority.authorityClass == "access-subnet-pool")
  and ($remoteV6Authority.childPurpose == "tenant-or-access-assignment")
  and ($hostOnlyAuthority.authorityClass == "host-only-provider-prefix")
  and ($hostOnlyAuthority.childPurpose == "provider-endpoint-host-address")
  and ($hostOnlyAuthority.consumerEligibility.route == true)
  and ($hostOnlyAuthority.consumerEligibility.assignment == false)
  and ($local.overlayReachability["east-west"].peerSites == [ "acme.branch" ])
  and ($local.overlayReachability["east-west"].routes4 | any(.dst == "10.45.40.0/24" and .peerSite == "acme.branch"))
  and ($local.overlayReachability["east-west"].routes6 | any(.dst == "fd42:450:40::/64" and .peerSite == "acme.branch"))
  and ($local.overlayReachability["east-west"].routes6 | all(.dst != "fd42:450:40::1/128"))
  and ([local_overlay_routes[] | select((.route.dst // null) == "10.45.40.0/24")] | length) > 0
  and ([local_overlay_routes[] | select((.route.dst // null) == "fd42:450:40::/64")] | length) > 0
  and ([local_overlay_routes[] | select((.route.sourceFile // null) == "/run/pd/remote-client-host-only.prefix")] | length) == 0
' "${output_json}" >/dev/null || {
  echo "FAIL fs350-overlay-ledger-construction: NFM must classify remote overlay participant ledgers and reject host-only provider ledgers from overlay reachability" >&2
  jq '
    {
      remoteTenantPrefixOwners: .enterprise.acme.site.branch.tenantPrefixOwners,
      remotePrefixAuthority: .enterprise.acme.site.branch.prefixAuthority,
      localOverlayReachability: .enterprise.acme.site.ams.overlayReachability,
      localOverlayRoutes: [
        .enterprise.acme.site.ams.nodes
        | to_entries[]
        | . as $node
        | ($node.value.interfaces // {})
        | to_entries[]
        | (.value.routes.ipv4[]?, .value.routes.ipv6[]?)
        | { node: $node.key, route: . }
        | select(
            (.route.intent.kind // null) == "overlay-reachability"
            and (.route.overlay // null) == "east-west"
            and (.route.peerSite // null) == "acme.branch"
          )
      ]
    }
  ' "${output_json}" >&2
  exit 1
}

pass_timed "fs350-overlay-ledger-construction"
