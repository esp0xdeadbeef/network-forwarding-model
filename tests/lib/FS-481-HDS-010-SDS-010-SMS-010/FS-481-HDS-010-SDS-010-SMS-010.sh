#!/usr/bin/env bash
set -euo pipefail

# GAMP-ID: FS-481-HDS-010-SDS-010-SMS-010
# GAMP-SCOPE: software-module-test
#
# Construction test for the boundary selection shape: the multipath member set
# is scoped to one route selection key and therefore to one address family, so
# a member whose default belongs to another family must not be admitted.
#
# The fixture names three eligible egress members on one access unit:
#   core-dual  IPv4 + IPv6
#   core-v4    IPv4 only
#   core-v6    IPv6 only
# A family-blind membership question puts all three in both families.

ROOT="${NETWORK_FORWARDING_MODEL_ROOT:-${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}}"
LABS="${NETWORK_LABS_PATH:-/home/deadbeef/github/network-labs}"
TRACE="FS-481-HDS-010-SDS-010-SMS-010"

result="$(nix eval --impure --json --expr "
  let
    nfm = builtins.getFlake (toString ${ROOT});
    source = import ${LABS}/GAMP/SMT/${TRACE}/intent.nix;
    compiled = nfm.inputs.network-compiler.lib.compile builtins.currentSystem source;
    forwarding = nfm.libBySystem.\${builtins.currentSystem}.model compiled;
    us = forwarding.enterprise.mini-smt.site.smt-shape.nodes.upstream-selector;
    laneNames = builtins.filter
      (n: builtins.match \".*--access-access-multi--uplink-.*\" n != null)
      (builtins.attrNames us.interfaces);
    viasOf = laneName: family:
      let
        routeFamily = if family == \"ipv4\" then \"ipv4\" else \"ipv6\";
        viaField = if family == \"ipv4\" then \"via4\" else \"via6\";
        defaults = builtins.filter
          (r: (r.multipath or null) != null && (r.dst == \"0.0.0.0/0\" || r.dst == \"::/0\"))
          (builtins.filter (x: x != null) (map (n: null) [ ]) ++
           (if us.interfaces.\${laneName}.routes ? \${routeFamily}
            then us.interfaces.\${laneName}.routes.\${routeFamily}
            else [ ]));
      in builtins.sort (a: b: a < b) (map (r: r.\${viaField}) defaults);
    authorityMissing = laneName:
      builtins.length (builtins.filter
        (r: (r.multipath or null) != null && ((r.multipath.authority or null) == null))
        ((us.interfaces.\${laneName}.routes.ipv4 or [ ]) ++ (us.interfaces.\${laneName}.routes.ipv6 or [ ]))) > 0;
  in {
    lanes = map (n: {
      lane = n;
      v4 = viasOf n \"ipv4\";
      v6 = viasOf n \"ipv6\";
      authorityMissing = authorityMissing n;
    }) laneNames;
  }
")"

# Every per-uplink lane of the access unit carries the same complete member set
# for that family. Each set has exactly two members because one of the three
# cores is single-family.
jq -e '
  (.lanes | length) == 3
  and ([ .lanes[] | (.v4 | length) == 2 ] | all)
  and ([ .lanes[] | (.v6 | length) == 2 ] | all)
  and ([ .lanes[] | (.v4 != .v6) ] | all)
  and ([ .lanes[] | (.authorityMissing | not) ] | all)
' <<<"$result" >/dev/null || {
  echo "FAIL ${TRACE}: every lane must carry a per-family member set of exactly two eligible cores" >&2
  jq '.' <<<"$result" >&2
  exit 1
}

# core-v4 is 10.81.1.6 and core-v6 is fd42:481:fe::8 in this fixture. The IPv4
# set must hold core-v4 and not core-v6; the IPv6 set must hold core-v6 and not
# core-v4. core-dual (10.81.1.4 / fd42:481:fe::4) is in both.
jq -e '
  def allLanes(f): [ .lanes[] | f ];
  allLanes(.v4 | index("10.81.1.6") != null)
  and allLanes(.v4 | index("10.81.1.4") != null)
  and allLanes(.v4 | index("fd42:481:fe:0:0:0:0:8") == null)
  and allLanes(.v6 | index("fd42:481:fe:0:0:0:0:8") != null)
  and allLanes(.v6 | index("fd42:481:fe:0:0:0:0:4") != null)
  and allLanes(.v6 | index("10.81.1.6") == null)
' <<<"$result" >/dev/null || {
  echo "FAIL ${TRACE}: a single-family core leaked into the other family member set" >&2
  jq '.' <<<"$result" >&2
  exit 1
}

echo "PASS ${TRACE}: NFM scopes the multipath member set to the family of the selection key"

# Seeded negative: give every member a default in both families. The two
# family member sets must then collapse to the same three cores, which proves
# the split came from per-family default presence, not from the member names.
seeded="$(nix eval --impure --json --expr "
  let
    nfm = builtins.getFlake (toString ${ROOT});
    source = import ${LABS}/GAMP/SMT/${TRACE}/intent.nix;
    base = source.mini-smt.smt-shape;
    bothFamilyUplink = { ipv4 = [ \"0.0.0.0/0\" ]; ipv6 = [ \"::/0\" ]; };
    bothFamilies = base // {
      topology = base.topology // {
        nodes = base.topology.nodes // {
          core-v4 = { role = \"core\"; uplinks.isp-v4 = bothFamilyUplink; };
          core-v6 = { role = \"core\"; uplinks.isp-v6 = bothFamilyUplink; };
        };
      };
    };
    compiled = nfm.inputs.network-compiler.lib.compile builtins.currentSystem {
      mini-smt = { smt-shape = bothFamilies; };
    };
    forwarding = nfm.libBySystem.\${builtins.currentSystem}.model compiled;
    us = forwarding.enterprise.mini-smt.site.smt-shape.nodes.upstream-selector;
    laneNames = builtins.filter
      (n: builtins.match \".*--access-access-multi--uplink-.*\" n != null)
      (builtins.attrNames us.interfaces);
    viasOf = laneName: family:
      let
        viaField = if family == \"ipv4\" then \"via4\" else \"via6\";
        defaults = builtins.filter
          (r: (r.multipath or null) != null && (r.dst == \"0.0.0.0/0\" || r.dst == \"::/0\"))
          (if us.interfaces.\${laneName}.routes ? \${family}
           then us.interfaces.\${laneName}.routes.\${family}
           else [ ]);
      in builtins.sort (a: b: a < b) (map (r: r.\${viaField}) defaults);
  in {
    lanes = map (n: { lane = n; v4 = viasOf n \"ipv4\"; v6 = viasOf n \"ipv6\"; }) laneNames;
  }
")"

jq -e '
  (.lanes | length) == 3
  and ([ .lanes[] | (.v4 | length) == 3 ] | all)
  and ([ .lanes[] | (.v6 | length) == 3 ] | all)
' <<<"$seeded" >/dev/null || {
  echo "FAIL ${TRACE}: dual-stack members must put all three cores in both family sets" >&2
  jq '.' <<<"$seeded" >&2
  exit 1
}

echo "PASS ${TRACE}: dual-stack members put every core in both family sets"
