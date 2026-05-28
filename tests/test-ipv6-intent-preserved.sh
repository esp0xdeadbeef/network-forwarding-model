#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: SMT-NFM-IPV6-INTENT-001
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
      local.ipv4 = "10.0.0.0/24";
      p2p.ipv4 = "10.0.1.0/24";
      p2p.ipv6 = "fd42:0:0:1000::/118";
    };

    ipv6 = {
      pd = {
        delegatedPrefixLength = 56;
        perTenantPrefixLength = 64;
        uplink = "wan";
      };
      tenants = {
        client.mode = "dhcpv6";
        mgmt = {
          mode = "static";
          prefixes = [ "2001:db8:10::/64" ];
        };
      };
    };

    attachments = [
      { unit = "access1"; kind = "tenant"; name = "client"; }
    ];

    domains = {
      externals = [ { kind = "external"; name = "wan"; } ];
      tenants = [
        { kind = "tenant"; name = "client"; ipv4 = "10.10.0.0/24"; ipv6 = "fd42:10:a::/64"; }
      ];
    };

    communicationContract.relations = [
      {
        id = "allow-client-to-wan";
        priority = 100;
        from = { kind = "tenant"; name = "client"; };
        to = { kind = "external"; uplinks = [ "wan" ]; };
        trafficType = "any";
        action = "allow";
      }
    ];

    transit.ordering = [
      [ "access1" "downstream1" ]
      [ "downstream1" "policy1" ]
      [ "policy1" "upstream1" ]
      [ "upstream1" "core1" ]
    ];

    units = {
      access1.role = "access";
      downstream1.role = "downstream-selector";
      policy1.role = "policy";
      upstream1.role = "upstream-selector";
      core1 = {
        role = "core";
        uplinks.wan.ipv4 = [ "0.0.0.0/0" ];
        uplinks.wan.ipv6 = [ "::/0" ];
      };
    };
  };
}
NIX

nix run "${repo_root}#compile-and-build-forwarding-model" -- "${input_nix}" >"${output_json}"

jq -e '
  .enterprise.acme.site.ams.ipv6.pd.delegatedPrefixLength == 56
  and .enterprise.acme.site.ams.ipv6.pd.perTenantPrefixLength == 64
  and .enterprise.acme.site.ams.ipv6.pd.uplink == "wan"
  and .enterprise.acme.site.ams.ipv6.tenants.client.mode == "dhcpv6"
  and .enterprise.acme.site.ams.ipv6.tenants.mgmt.mode == "static"
  and .enterprise.acme.site.ams.ipv6.tenants.mgmt.prefixes == [ "2001:db8:10::/64" ]
' "${output_json}" >/dev/null || {
  echo "FAIL ipv6-intent-preserved: NFM dropped compiler IPv6 PD intent" >&2
  jq '.enterprise.acme.site.ams.ipv6' "${output_json}" >&2
  exit 1
}

pass_timed "ipv6-intent-preserved"
