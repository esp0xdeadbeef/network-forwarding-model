#!/usr/bin/env bash
set -euo pipefail

# GAMP-ID: FS-540-HDS-010-SDS-010-SMS-042
# GAMP-SCOPE: software-module-test
#
# Recursive DNS Projection Non-Interference — Network Forwarding Model
#
# Proves that NFM route-atom projection preserves unrelated records when
# recursive DNS relations are added or removed.

ROOT="${NETWORK_FORWARDING_MODEL_ROOT:-${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}}"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

# Build Nix expression file to avoid string-escaping issues
cat >"$TMPDIR/eval.nix" <<'NIX'
let
  nfm = builtins.getFlake (toString __ROOT__);
  lib = nfm.inputs.nixpkgs.lib;

  nodes = {
    access-vlan2 = {
      role = "access";
      attachments = [ { kind = "tenant"; name = "clients"; } ];
    };
    access-vlan7 = {
      role = "access";
      attachments = [ { kind = "tenant"; name = "clients"; } ];
    };
    downstream = { role = "downstream-selector"; };
    policy = { role = "policy"; };
    upstream = { role = "upstream-selector"; };
    core-primary = {
      role = "core";
      uplinks = {
        wan-vlan4 = {
          ipv4 = [ "0.0.0.0/0" ];
          ipv6 = [ "::/0" ];
        };
      };
    };
  };

  links = [
    [ "access-vlan2" "downstream" ]
    [ "access-vlan7" "downstream" ]
    [ "downstream" "policy" ]
    [ "policy" "upstream" ]
    [ "upstream" "core-primary" ]
  ];

  nonDnsContract = {
    trafficTypes = [
      { name = "https"; match = [ { proto = "tcp"; family = "any"; dports = [ 443 ]; } ]; }
      { name = "icmp"; match = [ { proto = "icmp"; family = "any"; } ]; }
      { name = "dns";   match = [ { proto = "udp"; family = "any"; dports = [ 53 ]; } ]; }
    ];
    services = [
      { name = "access-dns"; providers = [ "access-vlan2" "access-vlan7" ]; trafficType = "dns"; }
    ];
    relations = [
      {
        id = "allow-clients-to-wan-https";
        priority = 100;
        from = { kind = "tenant"; name = "clients"; };
        to = { kind = "external"; uplinks = [ "wan-vlan4" ]; };
        trafficType = "https";
        action = "allow";
        returnBehavior = "symmetric";
      }
      {
        id = "allow-clients-to-wan-icmp";
        priority = 110;
        from = { kind = "tenant"; name = "clients"; };
        to = { kind = "external"; uplinks = [ "wan-vlan4" ]; };
        trafficType = "icmp";
        action = "allow";
        returnBehavior = "symmetric";
      }
    ];
  };

  ipv6 = {
    internetMode = { clients = "delegated-prefix"; };
    delegatedPrefix = {
      source = "wan-vlan4";
      pools = { ipv6 = "2001:db8:dead:beef::/56"; };
    };
    tenants = {
      clients = {
        pools = { ipv6 = "2001:db8:dead:beef:f00d::/64"; };
      };
    };
  };

  siteBase = {
    pools = {
      p2p.ipv4 = "10.10.0.0/24";
      loopback.ipv4 = "10.19.0.0/24";
    };
    ownership = {
      prefixes = [
        { kind = "tenant"; name = "clients"; ipv4 = "10.20.10.0/24"; }
      ];
    };
    topology = { inherit nodes links; };
    communicationContract = nonDnsContract;
    inherit ipv6;
  };

  withDns = siteBase // {
    recursiveDnsIntent = {
      services = [
        { name = "core-dns"; providerNode = "core-primary";
          addressAuthority = "model-allocated-service-prefix";
          recursionMode = "iterative"; trafficType = "dns"; }
      ];
      bindings = [
        { requesterScope = { kind = "service"; name = "access-dns"; };
          upstreamResolver = { kind = "service"; name = "core-dns"; node = "core-primary"; };
          egressSurface = { kind = "external"; uplinks = [ "wan-vlan4" ]; };
          allowedAddressFamilies = [ "ipv4" "ipv6" ]; }
      ];
    };
  };

  noDns = siteBase // {};

  withDnsPermuted = withDns // {
    recursiveDnsIntent = withDns.recursiveDnsIntent // {
      bindings = lib.reverseList withDns.recursiveDnsIntent.bindings;
    };
  };

  evalModel = source:
    let
      compiled = nfm.inputs.network-compiler.lib.compile
        builtins.currentSystem { mini-smt."FS-540-HDS-010-SDS-010-SMS-042" = source; };
    in nfm.libBySystem.${builtins.currentSystem}.model compiled;

  withDnsOut = evalModel withDns;
  noDnsOut = evalModel noDns;
  withDnsPermutedOut = evalModel withDnsPermuted;

  get = site: site.enterprise.mini-smt.site."FS-540-HDS-010-SDS-010-SMS-042";

  wd = get withDnsOut;
  nd = get noDnsOut;
  wpd = get withDnsPermutedOut;

  # Strip ALL DNS-provenance fields — anything that can be affected by DNS presence
  stripDns = site: builtins.removeAttrs site [
    "dns" "communicationContract" "trafficPaths" "relations"
    "recursiveDnsIntent" "services" "sourceAudit"
  ];

  nonDnsWd = stripDns wd;
  nonDnsNd = stripDns nd;
  nonDnsWpd = stripDns wpd;

  # --- Primary checks ---
  nonDnsMatch = nonDnsWd == nonDnsNd;
  dnsDiffers = wd.dns != nd.dns;
  permutedNonDnsMatch = nonDnsWpd == nonDnsWd;
  dnsPermutedMatch = wd.dns == wpd.dns;

  # --- Communication contract services ---
  commServicesWd = map (s: s.name) (wd.communicationContract.services or []);
  commServicesNd = map (s: s.name) (nd.communicationContract.services or []);
  coreDnsInWd = builtins.elem "core-dns" commServicesWd;
  coreDnsNotInNd = !builtins.elem "core-dns" commServicesNd;

  # --- IPv6 tenant keys preserved ---
  ipv6TenantKeysWd = builtins.attrNames (wd.ipv6.tenants or {});
  ipv6TenantKeysNd = builtins.attrNames (nd.ipv6.tenants or {});
  ipv6TenantsMatch = ipv6TenantKeysWd == ipv6TenantKeysNd;

  # --- Traffic paths cardinality ---
  pathCountWd = builtins.length (wd.trafficPaths or []);
  pathCountNd = builtins.length (nd.trafficPaths or []);

  # --- Permutation stability ---
  dnsServicesWd = map (s: s.name) (wd.dns.recursive.services or []);
  dnsServicesWpd = map (s: s.name) (wpd.dns.recursive.services or []);
  dnsServicesMatch = dnsServicesWd == dnsServicesWpd;
  dnsBindingsWd = builtins.length (wd.dns.recursive.bindings or []);
  dnsBindingsWpd = builtins.length (wpd.dns.recursive.bindings or []);
  dnsBindingsMatch = dnsBindingsWd == dnsBindingsWpd && dnsBindingsWd > 0;

  # --- No-DNS has empty recursive ---
  dnsRecServicesNd = builtins.length (nd.dns.recursive.services or []);
  dnsRecBindingsNd = builtins.length (nd.dns.recursive.bindings or []);

  # --- Diagnostic: attribute-level equality ---
  strippedWdAttrs = lib.sort builtins.lessThan (builtins.attrNames nonDnsWd);
  strippedNdAttrs = lib.sort builtins.lessThan (builtins.attrNames nonDnsNd);
  attrsMatch = strippedWdAttrs == strippedNdAttrs;
  attrDiffList = lib.filter
    (attr: nonDnsWd.${attr} != nonDnsNd.${attr})
    strippedWdAttrs;

in {
  inherit
    nonDnsMatch dnsDiffers permutedNonDnsMatch dnsPermutedMatch
    coreDnsInWd coreDnsNotInNd
    ipv6TenantsMatch pathCountWd pathCountNd
    dnsServicesMatch dnsBindingsMatch
    dnsRecServicesNd dnsRecBindingsNd
    attrsMatch attrDiffList
    ;
}
NIX

# Replace placeholder with actual ROOT path
sed -i "s|__ROOT__|${ROOT}|g" "$TMPDIR/eval.nix"

echo "=== FS-540-HDS-010-SDS-010-SMS-042 NFM: Recursive DNS Projection Non-Interference ==="

result="$(nix eval --impure --json -f "$TMPDIR/eval.nix")"

echo "--- Debug: diff attrs ---"
echo "$result" | jq '{attrsMatch, attrDiffList}' >&2

# MR1: Non-DNS records byte-equivalent
jq -e '.nonDnsMatch == true' <<<"$result" >/dev/null \
  && echo "PASS: MR1 - non-DNS records byte-equivalent" \
  || { echo "FAIL: MR1" >&2; jq '{nonDnsMatch, attrsMatch, attrDiffList}' <<<"$result" >&2; exit 1; }

# MR2: DNS output differs
jq -e '.dnsDiffers == true' <<<"$result" >/dev/null \
  && echo "PASS: MR2 - DNS output changes" \
  || { echo "FAIL: MR2" >&2; exit 1; }

# MR3: IPv6 tenant keys preserved
jq -e '.ipv6TenantsMatch == true' <<<"$result" >/dev/null \
  && echo "PASS: MR3 - IPv6 tenant keys preserved" \
  || { echo "FAIL: MR3" >&2; exit 1; }

# MR4: core-dns in communicationContract when DNS present
jq -e '.coreDnsInWd == true' <<<"$result" >/dev/null \
  && echo "PASS: MR4 - core-dns in communicationContract (DNS present)" \
  || { echo "FAIL: MR4" >&2; exit 1; }

# MR5: core-dns absent when no DNS
jq -e '.coreDnsNotInNd == true' <<<"$result" >/dev/null \
  && echo "PASS: MR5 - core-dns absent from communicationContract (no DNS)" \
  || { echo "FAIL: MR5" >&2; exit 1; }

# SN1: Permutation stability
jq -e '.permutedNonDnsMatch == true and .dnsPermutedMatch == true' <<<"$result" >/dev/null \
  && echo "PASS: SN1 - permuted DNS preserves non-DNS and DNS output" \
  || { echo "FAIL: SN1" >&2; exit 1; }

# SN2: DNS services/bindings stable after permutation
jq -e '.dnsServicesMatch == true and .dnsBindingsMatch == true' <<<"$result" >/dev/null \
  && echo "PASS: SN2 - DNS services and bindings stable after permutation" \
  || { echo "FAIL: SN2" >&2; exit 1; }

# SN3: No-DNS has empty DNS recursive
jq -e '.dnsRecServicesNd == 0 and .dnsRecBindingsNd == 0' <<<"$result" >/dev/null \
  && echo "PASS: SN3 - no-DNS variant has zero recursive DNS (no silent invention)" \
  || { echo "FAIL: SN3" >&2; exit 1; }

echo ""
echo "--- Cardinality ---"
echo "  trafficPaths: $(jq -r '.pathCountWd' <<<"$result") (DNS) vs $(jq -r '.pathCountNd' <<<"$result") (no-DNS)"

echo ""
echo "=== FS-540-HDS-010-SDS-010-SMS-042 NFM: ALL CHECKS PASSED ==="
