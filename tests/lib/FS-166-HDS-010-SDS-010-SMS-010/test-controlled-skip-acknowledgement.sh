#!/usr/bin/env bash
# GAMP-ID: FS-166-HDS-010-SDS-010-SMS-010
# GAMP-SCOPE: software-module-test; repository-owned skip acknowledgement
set -euo pipefail

ROOT="${NETWORK_FORWARDING_MODEL_ROOT:-${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}}"

nix eval --impure --json --expr '
  let
    api = (builtins.getFlake "path:'"$ROOT"'").libBySystem.${builtins.currentSystem};
    skip = api.controlledSkip;
    acknowledgement = api.controlledSkipAcknowledgement {
      traceId = "FS-166-HDS-010-SDS-010-SMS-010";
      declaredRepository = skip.repository;
      lockedRepositoryRevision = skip.repositoryRevision;
      declaredStageIndex = skip.stageIndex;
      declaredNormalInputContract = skip.normalInputContract;
      replacementContract = "network-control-plane-model-input/v1";
      expectedReplacementContract = "network-control-plane-model-input/v1";
      declaredFirstActiveBoundary = "network-control-plane-model";
      expectedFirstActiveBoundary = "network-control-plane-model";
      reason = "controlled replacement starts at CPM input";
      declaredPreviousStage = skip.previousStage;
      declaredNextStage = skip.nextStage;
      replacementIdentity = "fixture-cpm-input";
      replacementDigest = builtins.hashString "sha256" "fixture-cpm-input";
    };
  in
  assert acknowledgement.payloadAccessed == false;
  assert acknowledgement.transformationStarted == false;
  assert acknowledgement.acknowledgementCount == 1;
  assert builtins.stringLength acknowledgement.acknowledgementDigest == 64;
  acknowledgement
' >/dev/null

set +e
diagnostic="$({ nix eval --impure --json --expr '
  let
    api = (builtins.getFlake "path:'"$ROOT"'").libBySystem.${builtins.currentSystem};
    skip = api.controlledSkip;
  in
  api.controlledSkipAcknowledgement {
    traceId = "FS-166-HDS-010-SDS-010-SMS-010";
    declaredRepository = skip.repository;
    lockedRepositoryRevision = skip.repositoryRevision;
    declaredStageIndex = skip.stageIndex;
    declaredNormalInputContract = skip.normalInputContract;
    replacementContract = "network-control-plane-model-input/v1";
    expectedReplacementContract = "network-control-plane-model-input/v1";
    declaredFirstActiveBoundary = "network-control-plane-model";
    expectedFirstActiveBoundary = "network-control-plane-model";
    reason = "seeded next-stage negative";
    declaredPreviousStage = skip.previousStage;
    declaredNextStage = "network-realization-model";
    replacementIdentity = "fixture-cpm-input";
    replacementDigest = builtins.hashString "sha256" "fixture-cpm-input";
  }
'; } 2>&1)"
status=$?
set -e

[[ "$status" -ne 0 ]]
grep -Fq 'NS_SKIP_NEXT_STAGE_INVALID: /nextStage:' <<<"$diagnostic"

echo "PASS controlled-skip-acknowledgement network-forwarding-model"
