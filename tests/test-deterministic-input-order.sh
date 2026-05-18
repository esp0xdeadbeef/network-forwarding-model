#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

input_a="${tmpdir}/input-a.nix"
input_b="${tmpdir}/input-b.nix"
out_a="${tmpdir}/out-a.json"
out_b="${tmpdir}/out-b.json"

cat >"${input_a}" <<'NIX'
{
  sites.acme.ams = {
    addressPools = { local.ipv4 = "10.0.0.0/24"; p2p.ipv4 = "10.0.1.0/24"; p2p.ipv6 = "fd42:0:0:1000::/118"; };
    attachments = [
      { unit = "access1"; kind = "tenant"; name = "tenant-a"; }
      { unit = "access2"; kind = "tenant"; name = "tenant-b"; }
    ];
    domains = {
      externals = [ { kind = "external"; name = "wan"; } ];
      tenants = [
        { kind = "tenant"; name = "tenant-a"; ipv4 = "10.10.0.0/24"; ipv6 = "fd42:10:a::/64"; }
        { kind = "tenant"; name = "tenant-b"; ipv4 = "10.20.0.0/24"; ipv6 = "fd42:10:b::/64"; }
      ];
    };
    communicationContract.relations = [
      { id = "allow-a-wan"; priority = 100; from = { kind = "tenant"; name = "tenant-a"; }; to = { kind = "external"; uplinks = [ "wan" ]; }; trafficType = "any"; action = "allow"; }
      { id = "allow-b-wan"; priority = 110; from = { kind = "tenant"; name = "tenant-b"; }; to = { kind = "external"; uplinks = [ "wan" ]; }; trafficType = "any"; action = "allow"; }
    ];
    transit.ordering = [
      [ "access1" "downstream1" ] [ "access2" "downstream1" ]
      [ "downstream1" "policy1" ] [ "policy1" "upstream1" ] [ "upstream1" "core1" ]
    ];
    units = {
      access1.role = "access"; access2.role = "access"; downstream1.role = "downstream-selector";
      policy1.role = "policy"; upstream1.role = "upstream-selector";
      core1 = { role = "core"; uplinks.wan.ipv4 = [ "0.0.0.0/0" ]; uplinks.wan.ipv6 = [ "::/0" ]; };
    };
  };
}
NIX

cat >"${input_b}" <<'NIX'
{
  sites.acme.ams = {
    units = {
      core1 = { uplinks.wan.ipv6 = [ "::/0" ]; uplinks.wan.ipv4 = [ "0.0.0.0/0" ]; role = "core"; };
      upstream1.role = "upstream-selector"; policy1.role = "policy"; downstream1.role = "downstream-selector";
      access2.role = "access"; access1.role = "access";
    };
    transit.ordering = [
      [ "access2" "downstream1" ] [ "access1" "downstream1" ]
      [ "downstream1" "policy1" ] [ "policy1" "upstream1" ] [ "upstream1" "core1" ]
    ];
    domains = {
      tenants = [
        { ipv6 = "fd42:10:b::/64"; ipv4 = "10.20.0.0/24"; name = "tenant-b"; kind = "tenant"; }
        { ipv6 = "fd42:10:a::/64"; ipv4 = "10.10.0.0/24"; name = "tenant-a"; kind = "tenant"; }
      ];
      externals = [ { name = "wan"; kind = "external"; } ];
    };
    communicationContract.relations = [
      { action = "allow"; trafficType = "any"; to = { uplinks = [ "wan" ]; kind = "external"; }; from = { name = "tenant-b"; kind = "tenant"; }; priority = 110; id = "allow-b-wan"; }
      { action = "allow"; trafficType = "any"; to = { uplinks = [ "wan" ]; kind = "external"; }; from = { name = "tenant-a"; kind = "tenant"; }; priority = 100; id = "allow-a-wan"; }
    ];
    attachments = [
      { name = "tenant-b"; kind = "tenant"; unit = "access2"; }
      { name = "tenant-a"; kind = "tenant"; unit = "access1"; }
    ];
    addressPools = { p2p.ipv6 = "fd42:0:0:1000::/118"; p2p.ipv4 = "10.0.1.0/24"; local.ipv4 = "10.0.0.0/24"; };
  };
}
NIX

jq_projection='
  .enterprise.acme.site.ams
  | {
      links: (
        .links
        | to_entries
        | map({
            key,
            id: .value.id,
            kind: .value.kind,
            members: (.value.members | sort),
            lane: (.value.lane // null),
            laneMeta: (.value.laneMeta // {})
          })
        | sort_by(.key)
      ),
      transitOrdering: ((.transit.ordering // []) | sort),
      routes: (
        [
          .nodes
          | to_entries[] as $node
          | ($node.value.interfaces // {})
          | to_entries[] as $iface
          | (($iface.value.routes.ipv4 // [])[]?, ($iface.value.routes.ipv6 // [])[]?)
          | {
              node: $node.key,
              iface: $iface.key,
              dst,
              proto,
              intent: (.intent.kind // null),
              via4: (.via4 // null),
              via6: (.via6 // null),
              lane: (.lane // null)
            }
        ]
        | sort_by([.node, .iface, .dst, .proto, (.intent // ""), (.via4 // ""), (.via6 // ""), (.lane | tostring)])
      )
    }
'

nix run "${repo_root}#compile-and-build-forwarding-model" -- "${input_a}" | jq -S "${jq_projection}" >"${out_a}"
nix run "${repo_root}#compile-and-build-forwarding-model" -- "${input_b}" | jq -S "${jq_projection}" >"${out_b}"

diff -u "${out_a}" "${out_b}"

echo "PASS deterministic-input-order"
