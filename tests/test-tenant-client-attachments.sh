#!/usr/bin/env bash
# GAMP-ID: SMT-NFM-TENANT-CLIENT-001
# GAMP-SCOPE: software-module-test
set - euo pipefail

  repo_root="$(git rev-parse --show-toplevel)"
source "${repo_root}/tests/lib/timing.sh"
tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

start_ms="$(test_now_ms)"
input_nix="${tmpdir}/input.nix"
input_json="${tmpdir}/input.json"
model_json="${tmpdir}/model.json"

cat >"${input_nix}" <<'EOF'
{
sites.acme.ams = {
addressPools = {
local.ipv4 = "10.0.0.0/24";
local.ipv6 = "fd42:0:0:1900::/64";
p2p.ipv4 = "10.0.1.0/24";
p2p.ipv6 = "fd42:0:0:1000::/64";
};

domains = {
tenants = [
{
kind = "tenant";
name = "client";
ipv4 = "10.20.20.0/24";
ipv6 = "fd42:dead:beef:20::/64";
}
];
externals = [ { kind = "external"; name = "wan"; } ];
};

communicationContract.relations = [
{
id = "allow-client-wan";
priority = 100;
from = { kind = "tenant"; name = "client"; };
to = { kind = "external"; name = "wan"; };
trafficType = "any";
action = "allow";
}
];

topology.nodes = {
access-client = {
role = "access";
attachments = [ { kind = "tenant"; name = "client"; } ];
};
core-nebula = {
role = "core";
attachments = [ { kind = "tenant"; name = "client"; } ];
uplinks.east-west.ipv4 = [ "100.96.0.0/24" ];
};
core-wan = {
role = "core";
uplinks.wan.ipv4 = [ "0.0.0.0/0" ];
uplinks.wan.ipv6 = [ "::/0" ];
};
downstream.role = "downstream-selector";
policy.role = "policy";
upstream.role = "upstream-selector";
};

topology.links = [
[ "access-client" "downstream" ]
[ "downstream" "policy" ]
[ "policy" "upstream" ]
[ "upstream" "core-nebula" ]
[ "upstream" "core-wan" ]
];
};
}
EOF

nix eval --json --impure --expr "import ${input_nix}" >"${input_json}"
S88_NFM_PROFILE_SKIP_ROUTING=1 nix run "${repo_root}#debug" -- "${input_json}" >"${model_json}"

if jq -e '
.enterprise.acme.site.ams.nodes as $nodes
| $nodes."access-client".interfaces."tenant-client" as $access
| $nodes."core-nebula".interfaces."tenant-client" as $core
| $access.addr4 == "10.20.20.1/24"
    and $access.addr6 == "fd42:dead:beef:20:0:0:0:1/64"
and $access.dhcp == false
and $access.acceptRA == false
and (($access.routes.ipv4 // []) | any(.dst == "10.20.20.0/24"))
and (($access.routes.ipv6 // []) | any(.dst == "fd42:dead:beef:0020:0000:0000:0000:0000/64"))
and ($core.addr4 == null)
and ($core.addr6 == null)
and $core.dhcp == true
and $core.acceptRA == true
and (($core.routes.ipv4 // []) == [])
and (($core.routes.ipv6 // []) == [])
' "${model_json}" >/dev/null; then
pass_timed "tenant-client-attachments" "${start_ms}"
else
echo "FAIL tenant-client-attachments" >&2
jq '.enterprise.acme.site.ams.nodes
| {
access: ."access-client".interfaces."tenant-client",
core: ."core-nebula".interfaces."tenant-client"
}' "${model_json}" >&2
exit 1
fi
