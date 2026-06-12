#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-181-HDS-010-SDS-020-SMS-010 — Policy Authority Records CMC test

repo_root="$(git rev-parse --show-toplevel)"
source "${repo_root}/tests/lib/timing.sh"
start_ms="$(test_now_ms)"
tmpd="$(mktemp -d)"
trap 'rm -rf "$tmpd"' EXIT

archive_json="$tmpd/archive.json"
nix flake archive --json "path:$repo_root" >"$archive_json"
compiler_path="$(ARCHIVE_JSON="$archive_json" nix eval --impure --raw --expr '
  let a=builtins.fromJSON(builtins.readFile(builtins.getEnv "ARCHIVE_JSON"));
  in a.inputs."network-compiler".path or (throw "missing network-compiler")
')"

PASS=0; FAIL=0
pass() { echo "PASS $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL $1"; FAIL=$((FAIL+1)); }

# ── P1: Positive — graph path + policy tuple produces authority ──
echo "=== P1: Positive case ==="
PI="$tmpd/p1.nix"; PC="$tmpd/p1-compiler.json"; PN="$tmpd/p1-nfm.json"
cat >"$PI" <<'NIX'
{ esp0xdeadbeef={"site-a"={
  pools={p2p.ipv4="10.10.0.0/24";loopback.ipv4="10.19.0.0/24";};
  ownership.prefixes=[{kind="tenant";name="client";ipv4="10.20.20.0/24";}];
  communicationContract={
    trafficTypes=[{name="https";match=[{proto="tcp";family="any";dports=[443];}];}];
    relations=[{id="allow-client-wan";priority=100;from.kind="tenant";from.name="client";to.kind="external";to.uplinks=["wan"];trafficType="https";action="allow";}];
  };
  topology.nodes={
    access-client={role="access";attachments=[{kind="tenant";name="client";}];};
    downstream.role="downstream-selector";policy.role="policy";upstream.role="upstream-selector";
    core-wan={role="core";uplinks.wan.ipv4=["0.0.0.0/0"];};
  };
  topology.links=[["access-client" "downstream"]["downstream" "policy"]["policy" "upstream"]["upstream" "core-wan"]];
};};}
NIX

nix run --no-warn-dirty "path:$compiler_path#compile" -- "$PI" >"$PC" || { fail "P1-compile"; exit 1; }
nix run "$repo_root#compile-and-build-forwarding-model" -- "$PI" >"$PN" || { fail "P1-nfm"; exit 1; }

jq -e '[.sites.esp0xdeadbeef."site-a".trafficPaths[]|select(.relationId=="allow-client-wan")][0].action=="allow"' "$PC" >/dev/null \
  && pass "P1a-compiler-trafficPath" || fail "P1a"
jq -e '.enterprise.esp0xdeadbeef.site."site-a".communicationContract.allowedRelations|map(select(.id=="allow-client-wan"))|length==1' "$PN" >/dev/null \
  && pass "P1b-NFM-allowedRelation" || fail "P1b"

# ── N1: Deny tuple → no authority (lane routes) ──
echo ""
echo "=== N1: Deny-only tuple — no authority ==="
NI="$tmpd/n1.nix"; NC="$tmpd/n1-compiler.json"; NN="$tmpd/n1-nfm.json"
cat >"$NI" <<'NIX'
{ esp0xdeadbeef={"site-b"={
  pools={p2p.ipv4="10.10.0.0/24";loopback.ipv4="10.19.0.0/24";};
  ownership.prefixes=[{kind="tenant";name="client";ipv4="10.20.20.0/24";}{kind="tenant";name="mgmt";ipv4="10.20.30.0/24";}];
  communicationContract={
    trafficTypes=[{name="https";match=[{proto="tcp";family="any";dports=[443];}];}];
    relations=[
      {id="deny-client";priority=100;from.kind="tenant";from.name="client";to.kind="external";to.uplinks=["wan"];trafficType="https";action="deny";}
      {id="allow-mgmt";priority=200;from.kind="tenant";from.name="mgmt";to.kind="external";to.uplinks=["wan"];trafficType="https";action="allow";}
    ];
  };
  topology.nodes={
    access-client={role="access";attachments=[{kind="tenant";name="client";}];};
    access-mgmt={role="access";attachments=[{kind="tenant";name="mgmt";}];};
    downstream.role="downstream-selector";policy.role="policy";upstream.role="upstream-selector";
    core-wan={role="core";uplinks.wan.ipv4=["0.0.0.0/0"];};
  };
  topology.links=[["access-client" "downstream"]["access-mgmt" "downstream"]["downstream" "policy"]["policy" "upstream"]["upstream" "core-wan"]];
};};}
NIX

nix run --no-warn-dirty "path:$compiler_path#compile" -- "$NI" >"$NC" || { fail "N1-compile"; exit 1; }
nix run "$repo_root#compile-and-build-forwarding-model" -- "$NI" >"$NN" || { fail "N1-nfm"; exit 1; }

# Compiler DOES produce trafficPath for deny (it's a path mapping, still valid)
jq -e '[.sites.esp0xdeadbeef."site-b".trafficPaths[]|select(.relationId=="deny-client")]|length>0' "$NC" >/dev/null \
  && pass "N1a-compiler-deny-has-path-mapping" || fail "N1a"

# NFM must NOT produce lane-default routes for deny-only client
jq -e '[.enterprise.esp0xdeadbeef.site."site-b".nodes|to_entries[]|.value.interfaces|to_entries[]|.value.routes.ipv4[]?|select(.lane.access=="client")]|length==0' "$NN" >/dev/null \
  && pass "N1b-no-lane-routes-for-deny-only" || fail "N1b"

# Allowed mgmt relation preserved in NFM output
jq -e '.enterprise.esp0xdeadbeef.site."site-b".communicationContract.allowedRelations|map(select(.id=="allow-mgmt"))|length==1' "$NN" >/dev/null \
  && pass "N1c-mgmt-allowedRelation-preserved" || fail "N1c"

# ── N2: Authority not widened beyond modeled tuple ──
echo ""
echo "=== N2: No authority widening ==="
WI="$tmpd/n2.nix"; WC="$tmpd/n2-compiler.json"; WN="$tmpd/n2-nfm.json"
cat >"$WI" <<'NIX'
{ esp0xdeadbeef={"site-c"={
  pools={p2p.ipv4="10.10.0.0/24";loopback.ipv4="10.19.0.0/24";};
  ownership.prefixes=[{kind="tenant";name="client";ipv4="10.20.40.0/24";}];
  communicationContract={
    trafficTypes=[
      {name="https";match=[{proto="tcp";family="any";dports=[443];}];}
      {name="http";match=[{proto="tcp";family="any";dports=[80];}];}
    ];
    relations=[{id="allow-https";priority=100;from.kind="tenant";from.name="client";to.kind="external";to.uplinks=["wan"];trafficType="https";action="allow";}];
  };
  topology.nodes={
    access-client={role="access";attachments=[{kind="tenant";name="client";}];};
    downstream.role="downstream-selector";policy.role="policy";upstream.role="upstream-selector";
    core-wan={role="core";uplinks.wan.ipv4=["0.0.0.0/0"];};
  };
  topology.links=[["access-client" "downstream"]["downstream" "policy"]["policy" "upstream"]["upstream" "core-wan"]];
};};}
NIX

nix run --no-warn-dirty "path:$compiler_path#compile" -- "$WI" >"$WC" || { fail "N2-compile"; exit 1; }
nix run "$repo_root#compile-and-build-forwarding-model" -- "$WI" >"$WN" || { fail "N2-nfm"; exit 1; }

jq -e '[.sites.esp0xdeadbeef."site-c".trafficPaths[]]|length==1 and .[0].relationId=="allow-https"' "$WC" >/dev/null \
  && pass "N2a-only-https-trafficPath" || fail "N2a"
jq -e '.enterprise.esp0xdeadbeef.site."site-c".communicationContract.allowedRelations|map(select(.trafficType=="http"))|length==0' "$WN" >/dev/null \
  && pass "N2b-no-http-in-allowedRelations" || fail "N2b"

echo ""
echo "=== Results: $PASS pass, $FAIL fail ==="
[ "$FAIL" -eq 0 ] && pass_timed "FS-181-HDS-010-SDS-020-SMS-010" "$start_ms" && exit 0
exit 1
