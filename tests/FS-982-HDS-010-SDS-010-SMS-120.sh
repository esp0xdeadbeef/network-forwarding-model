#!/usr/bin/env bash
# GAMP-ID: FS-982-HDS-010-SDS-010-SMS-120
# GAMP-SCOPE: software-module-test
set -euo pipefail

repo_root="${NETWORK_FORWARDING_MODEL_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
system="${NIX_SYSTEM:-x86_64-linux}"

REPO_ROOT="${repo_root}" NIX_SYSTEM="${system}" nix eval --impure --raw --expr '
  let
    repoRoot = builtins.getEnv "REPO_ROOT";
    system = builtins.getEnv "NIX_SYSTEM";
    flake = builtins.getFlake ("path:" + repoRoot);
    compiler = flake.inputs.network-compiler.libBySystem.${system};
    baseIntent = import (flake.inputs.network-compiler.outPath + "/tests/fixtures/single-uplink.nix");
    compiledBaseRaw = compiler.compileValue baseIntent;
    compiledBase = compiledBaseRaw // {
      sites.esp0xdeadbeef."site-a" = compiledBaseRaw.sites.esp0xdeadbeef."site-a" // {
        relations = map
          (relation:
            relation
            // (if (relation.action or null) == "allow" && !(relation ? returnBehavior)
                then { returnBehavior = "symmetric"; }
                else { }))
          compiledBaseRaw.sites.esp0xdeadbeef."site-a".relations;
      };
    };
    management = {
      required = true;
      interface = "modeled-management-surface";
      purpose = "hardware-management";
      managementOnly = true;
    };
    explicit = compiledBase // {
      sites.esp0xdeadbeef."site-a" = compiledBase.sites.esp0xdeadbeef."site-a" // {
        hostManagement = management;
      };
      meta.provenance.originalInputs.esp0xdeadbeef."site-a" =
        baseIntent.esp0xdeadbeef."site-a" // {
          hostManagement = management // { interface = "provenance-must-not-win"; };
        };
    };
    withoutExplicit = compiledBase // {
      meta.provenance.originalInputs.esp0xdeadbeef."site-a" =
        baseIntent.esp0xdeadbeef."site-a" // {
          hostManagement = management // { interface = "provenance-only"; };
        };
    };
    built = flake.libBySystem.${system}.build { input = explicit; };
    builtWithoutExplicit = flake.libBySystem.${system}.build { input = withoutExplicit; };
    site = built.enterprise.esp0xdeadbeef.site."site-a";
    provenanceOnlySite = builtWithoutExplicit.enterprise.esp0xdeadbeef.site."site-a";
    require = condition: message: if condition then true else throw message;
  in
    if
      require (site.hostManagement == management)
        "NFM changed or dropped the explicit compiler hostManagement atom"
      && require ((provenanceOnlySite.hostManagement or null) == null)
        "NFM admitted hostManagement from compiler provenance instead of explicit output"
    then "ok" else throw "unreachable"
' >/dev/null

echo "PASS FS-982-HDS-010-SDS-010-SMS-120 NFM host-management authority"
