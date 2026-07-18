#!/usr/bin/env bash
set -euo pipefail

# GAMP-ID: FS-525-HDS-010-SDS-010-SMS-010
# GAMP-SCOPE: software-module-test

ROOT="${NETWORK_FORWARDING_MODEL_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
LABS="${NETWORK_LABS_PATH:-/home/deadbeef/github/network-labs}"

result="$(nix eval --impure --json --expr "
  let
    nfm = builtins.getFlake (toString ${ROOT});
    source = import ${LABS}/GAMP/SMT/FS-525-HDS-010-SDS-010-SMS-010/intent.nix;
    compiled = nfm.inputs.network-compiler.lib.compile builtins.currentSystem source;
    forwarding = nfm.libBySystem.\${builtins.currentSystem}.model compiled;
  in forwarding.enterprise.mini-smt.site.FS-525-HDS-010-SDS-010-SMS-010
")"

jq -e '
  .dns.schemaVersion == 1
  and .dns.warnings == []
  and .dns.recursive.services[0].name == "core-dns"
  and .dns.recursive.services[0].providerNode == "core-primary"
  and (.communicationContract.services | map(select(.name == "core-dns")) | length) == 1
  and (.communicationContract.services | map(select(.name == "core-dns"))[0].providerNode) == "core-primary"
  and ([.communicationContract.allowedRelations[].id] | index("FS-525-HDS-010-SDS-010-SMS-010__access-dns-to-core-dns")) != null
  and ([.communicationContract.allowedRelations[]
    | select(.id == "FS-525-HDS-010-SDS-010-SMS-010__access-dns-to-core-dns")
    | .returnBehavior] == ["symmetric"])
  and ([.trafficPaths[]
    | select(.relationId == "FS-525-HDS-010-SDS-010-SMS-010__access-dns-to-core-dns")
    | .nodePath] == [[
      "access-dns",
      "downstream-selector",
      "policy",
      "upstream-selector",
      "core-primary"
    ]])
' <<<"$result" >/dev/null

if ! jq -e '[.dns.warnings[]? | .. | strings | select(
  test("(^|[^0-9])([0-9]{1,3}\\.){3}[0-9]{1,3}([^0-9]|$)")
  or test("^([0-9A-Fa-f]{0,4}:){2,}[0-9A-Fa-f]{0,4}(/[0-9]+)?$")
)] == []' <<<"$result" >/dev/null; then
  echo "FAIL: NFM DNS warnings leaked address material" >&2
  exit 1
fi

echo "PASS: NFM preserves compiler-owned named core DNS authority and path"

seeded="$(nix eval --impure --json --expr "
  let
    nfm = builtins.getFlake (toString ${ROOT});
    lib = nfm.inputs.nixpkgs.lib;
    source = import ${LABS}/GAMP/SMT/FS-525-HDS-010-SDS-010-SMS-010/intent.nix;
    base = source.mini-smt.FS-525-HDS-010-SDS-010-SMS-010;
    recursive = base.recursiveDnsIntent;
    service = builtins.head recursive.services;
    secondaryCore = {
      role = \"core\";
      uplinks.overlay-secondary-only = {
        ipv4 = [ \"0.0.0.0/0\" ];
        ipv6 = [ \"::/0\" ];
      };
    };
    ambiguous = base // {
      topology = base.topology // {
        nodes = base.topology.nodes // { core-secondary = secondaryCore; };
        links = base.topology.links ++ [ [ \"upstream-selector\" \"core-secondary\" ] ];
      };
      recursiveDnsIntent = recursive // {
        services = recursive.services ++ [ (service // { providerNode = \"core-secondary\"; }) ];
      };
    };
    evaluate = name: site:
      let
        compiled = nfm.inputs.network-compiler.lib.compile builtins.currentSystem {
          mini-smt = { \"\${name}\" = site; };
        };
      in (nfm.libBySystem.\${builtins.currentSystem}.model compiled)
        .enterprise.mini-smt.site.\"\${name}\";
    first = evaluate \"ambiguous\" ambiguous;
    permuted = evaluate \"permuted\" (ambiguous // {
      recursiveDnsIntent = ambiguous.recursiveDnsIntent // {
        services = lib.reverseList ambiguous.recursiveDnsIntent.services;
      };
    });
  in {
    firstWarnings = first.dns.warnings;
    permutedWarnings = permuted.dns.warnings;
    firstCoreServices = builtins.filter
      (entry: (entry.name or null) == \"core-dns\")
      first.communicationContract.services;
  }
")"

jq -e '
  ([.firstWarnings[].code] | index("DNS_CORE_BINDING_AMBIGUOUS")) != null
  and ([.firstWarnings[] | del(.site)] == [.permutedWarnings[] | del(.site)])
  and .firstCoreServices == []
  and all(.firstWarnings[]; .candidateIds == (.candidateIds | sort | unique))
' <<<"$seeded" >/dev/null

echo "PASS: NFM preserves deterministic fail-closed ambiguity warnings without inventing a provider"
