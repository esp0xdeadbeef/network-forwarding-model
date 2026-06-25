#!/usr/bin/env bash
# GAMP-ID: FS-166-HDS-010-SDS-010-SMS-900
# GAMP-SCOPE: software-module-test; NFM layer-entry warning/pass-through contract
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  echo "FAIL nfm-layer-entry-warning-contract: $*" >&2
  exit 1
}

nix eval --impure --expr "
  let
    flake = builtins.getFlake \"path:${repo_root}\";
    api = flake.libBySystem.\${builtins.currentSystem};
    require = cond: msg: if cond then true else throw msg;
    input = {
      pocKind = \"network-labs.synthetic-control-plane-input\";
      marker = \"FS-166-HDS-010-SDS-010-SMS-900\";
    };
    nfmConsumed = api.layerEntryEnvelope {
      entryBoundary = \"forwarding-model-input\";
      inherit input;
    };
    nfmSkipped = api.layerEntryEnvelope {
      entryBoundary = \"control-plane-input\";
      inherit input;
    };
    rendererEntry = api.layerEntryEnvelope {
      entryBoundary = \"renderer-input\";
      inherit input;
    };
    warningCodes = payload: map (warning: warning.code) payload.warnings;
  in
    require (nfmConsumed.repo == \"network-forwarding-model\")
      \"NFM envelope must identify issuing repo\"
    && require (nfmConsumed.repoSkipped == false)
      \"forwarding-model-input must not mark NFM skipped\"
    && require (nfmConsumed.warnings == [ ])
      \"forwarding-model-input must not emit NFM skip warning\"
    && require (nfmSkipped.repoSkipped == true)
      \"control-plane-input must mark NFM skipped\"
    && require (warningCodes nfmSkipped == [ \"WARN_LAYER_ENTRY_SKIPS_NFM\" ])
      \"control-plane-input must emit the NFM skip warning from NFM\"
    && require (nfmSkipped.input == input && nfmSkipped.output == input)
      \"NFM skipped envelope must pass through the normalized input attrset\"
    && require (rendererEntry.repoSkipped == true)
      \"renderer-input must mark NFM skipped\"
    && require (warningCodes rendererEntry == [ \"WARN_LAYER_ENTRY_SKIPS_NFM\" ])
      \"renderer-input must carry the NFM skip warning\"
" >/dev/null || fail "layer-entry NFM contract failed"

echo "PASS nfm-layer-entry-warning-contract"
