#!/usr/bin/env bash
set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

input_nix="${tmpdir}/input.nix"
ir_json="${tmpdir}/ir.json"
model_json="${tmpdir}/model.json"

cat >"${input_nix}" <<'EOF'
{
  sites.acme.ams = {
    addressPools.local.ipv4 = "10.0.0.0/24";
    addressPools.p2p.ipv4 = "10.0.1.0/24";
    domains.externals = [ { kind = "external"; name = "east-west"; } ];
    domains.tenants = [ { kind = "tenant"; name = "lan"; ipv4 = "10.20.10.0/24"; } ];
    attachments = [ { unit = "access"; kind = "tenant"; name = "lan"; } ];
    communicationContract.relations = [
      { id = "allow-lan-east-west"; priority = 100; from = { kind = "tenant"; name = "lan"; }; to = { kind = "external"; name = "east-west"; }; trafficType = "any"; action = "allow"; }
    ];
    transit.ordering = [
      [ "access" "downstream" ]
      [ "downstream" "policy" ]
      [ "policy" "upstream" ]
      [ "upstream" "core-overlay" ]
    ];
    transport.overlays = [
      {
        name = "east-west";
        peerSites = [ "acme.remote-a" "acme.remote-b" ];
        terminateOn = "core-overlay";
      }
    ];
    units = {
      access.role = "access";
      downstream.role = "downstream-selector";
      policy.role = "policy";
      upstream.role = "upstream-selector";
      core-overlay.role = "core";
      core-overlay.uplinks.east-west.ipv4 = [ "100.96.0.0/24" ];
    };
  };

  sites.acme.remote-a = {
    addressPools.local.ipv4 = "10.1.0.0/24";
    addressPools.p2p.ipv4 = "10.1.1.0/24";
    domains.externals = [ { kind = "external"; name = "east-west"; } ];
    domains.tenants = [ { kind = "tenant"; name = "remote-a"; ipv4 = "10.40.10.0/24"; } ];
    attachments = [ { unit = "access-a"; kind = "tenant"; name = "remote-a"; } ];
    communicationContract.relations = [
      { id = "allow-remote-a"; priority = 100; from = { kind = "tenant"; name = "remote-a"; }; to = { kind = "external"; name = "east-west"; }; trafficType = "any"; action = "allow"; }
    ];
    transit.ordering = [ [ "access-a" "downstream-a" ] [ "downstream-a" "policy-a" ] [ "policy-a" "upstream-a" ] [ "upstream-a" "core-a" ] ];
    transport.overlays = [ { name = "east-west"; peerSite = "acme.ams"; terminateOn = "core-a"; } ];
    units = {
      access-a.role = "access";
      downstream-a.role = "downstream-selector";
      policy-a.role = "policy";
      upstream-a.role = "upstream-selector";
      core-a.role = "core";
      core-a.uplinks.east-west.ipv4 = [ "100.96.0.0/24" ];
    };
  };

  sites.acme.remote-b = {
    addressPools.local.ipv4 = "10.2.0.0/24";
    addressPools.p2p.ipv4 = "10.2.1.0/24";
    domains.externals = [ { kind = "external"; name = "east-west"; } ];
    domains.tenants = [ { kind = "tenant"; name = "remote-b"; ipv4 = "10.60.10.0/24"; } ];
    attachments = [ { unit = "access-b"; kind = "tenant"; name = "remote-b"; } ];
    communicationContract.relations = [
      { id = "allow-remote-b"; priority = 100; from = { kind = "tenant"; name = "remote-b"; }; to = { kind = "external"; name = "east-west"; }; trafficType = "any"; action = "allow"; }
    ];
    transit.ordering = [ [ "access-b" "downstream-b" ] [ "downstream-b" "policy-b" ] [ "policy-b" "upstream-b" ] [ "upstream-b" "core-b" ] ];
    transport.overlays = [ { name = "east-west"; peerSite = "acme.ams"; terminateOn = "core-b"; } ];
    units = {
      access-b.role = "access";
      downstream-b.role = "downstream-selector";
      policy-b.role = "policy";
      upstream-b.role = "upstream-selector";
      core-b.role = "core";
      core-b.uplinks.east-west.ipv4 = [ "100.96.0.0/24" ];
    };
  };
}
EOF

nix eval --json --impure --expr "import ${input_nix}" >"${ir_json}"
nix run "${repo_root}#debug" -- "${ir_json}" >"${model_json}"

if jq -e '
  .enterprise.acme.site.ams.overlayReachability."east-west" as $overlay
  | $overlay.peerSites == [ "acme.remote-a", "acme.remote-b" ]
  and ($overlay.routes4 | any(.dst == "10.40.10.0/24" and .peerSite == "acme.remote-a"))
  and ($overlay.routes4 | any(.dst == "10.60.10.0/24" and .peerSite == "acme.remote-b"))
' "${model_json}" >/dev/null; then
  echo "PASS overlay-peer-sites"
else
  echo "FAIL overlay-peer-sites: FWM did not expand multi-peer overlay reachability" >&2
  exit 1
fi
