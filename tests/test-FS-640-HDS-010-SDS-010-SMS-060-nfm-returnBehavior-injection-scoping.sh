#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-640-HDS-010-SDS-010-SMS-060
# Construction test: NFM returnBehavior injection scoping
# Trace chain: URS → FS-640 → FS-640-HDS-010 → FS-640-HDS-010-SDS-010 → SMS-060
#
# Verifies normalizeCommunicationContract in compiler-input/sites/shape.nix
# injects returnBehavior="symmetric" on ALL allow relations per D18-NEW
# expansion, with tenant-to-tenant exclusion in both bidirectional and
# non-bidirectional paths per FS-640/FS-620.
#
# Seeded negatives (must fail before code fix):
#   N1: local tenant-to-tenant receives symmetric injection
#   N2: explicit returnBehavior overwritten
#   N3: local tenant-to-tenant with bidirectional receives symmetric injection

repo_root="$(git rev-parse --show-toplevel)"
source "${repo_root}/tests/lib/timing.sh"

start_ms="$(test_now_ms)"
export NFM_REPO_ROOT="${repo_root}"

fail() {
  printf 'FAIL FS-640-SMS-060 returnBehavior scoping: %s\n' "$*" >&2
  exit 1
}

# ── Common nix-eval helper ──
# Evaluates normalizeCommunicationContract on a JSON fixture.
# The fixture JSON must have a "communicationContract" key with "allowedRelations".
# Returns JSON array of the output allowedRelations.
eval_fixture() {
  local fixture_json="$1"   # JSON string of the site fixture
  local fixture_file="$2"   # temp file to write it to
  printf '%s' "$fixture_json" > "$fixture_file"
  nix eval --impure --json --expr '
    let
      repoRoot = builtins.getEnv "NFM_REPO_ROOT";
      flake = builtins.getFlake ("path:" + repoRoot);
      pkgs = flake.inputs.nixpkgs.legacyPackages.${builtins.currentSystem};
      lib = pkgs.lib;
      attrs = import (repoRoot + "/compiler-input/sites/attrs.nix") { inherit lib; };
      shape = import (repoRoot + "/compiler-input/sites/shape.nix") {
        inherit (attrs) getAttrPathOr hasAttrPath;
      };
      fixtureFile = builtins.getEnv "NFM_FIXTURE_FILE";
      fixture = builtins.fromJSON (builtins.readFile fixtureFile);
      result = shape.normalizeCommunicationContract fixture;
    in
      result.allowedRelations or []
  '
}

# ── Assertion helpers ──
assert_symmetric() {
  local label="$1" relations_json="$2"
  if ! printf '%s' "$relations_json" | jq -e '.[0].returnBehavior == "symmetric"' >/dev/null; then
    printf 'FAIL [%s]: expected returnBehavior="symmetric"\ngot: %s\n' "$label" "$relations_json" >&2
    exit 1
  fi
  echo "PASS [$label]: returnBehavior=\"symmetric\" injected"
}

assert_no_returnBehavior() {
  local label="$1" relations_json="$2"
  if printf '%s' "$relations_json" | jq -e '.[0] | has("returnBehavior")' >/dev/null 2>&1; then
    local actual
    actual="$(printf '%s' "$relations_json" | jq -r '.[0].returnBehavior // "PRESENT"')"
    printf 'FAIL [%s]: expected NO returnBehavior field, got="%s"\nfull: %s\n' "$label" "$actual" "$relations_json" >&2
    exit 1
  fi
  echo "PASS [$label]: no returnBehavior injected (one-way default preserved)"
}

assert_returnBehavior_equals() {
  local label="$1" relations_json="$2" expected="$3"
  local actual
  actual="$(printf '%s' "$relations_json" | jq -r '.[0].returnBehavior // "ABSENT"')"
  if [[ "$actual" != "$expected" ]]; then
    printf 'FAIL [%s]: expected returnBehavior="%s" got="%s"\n' "$label" "$expected" "$actual" >&2
    exit 1
  fi
  echo "PASS [$label]: returnBehavior=\"$expected\" preserved"
}

# ── Temp dir for fixture files ──
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

export NFM_FIXTURE_FILE="${tmpdir}/fixture.json"

# ═══════════════════════════════════════════════════════════════
# Positive case 1: trafficType="any" + non-local → symmetric
# ═══════════════════════════════════════════════════════════════
echo "=== Positive 1: trafficType=\"any\" non-local → symmetric ==="
pos1_json='{"communicationContract":{"allowedRelations":[{"id":"allow-media-to-wan","action":"allow","from":{"kind":"service","name":"media"},"to":{"kind":"external","uplinks":["wan"]},"trafficType":"any"}]}}'
pos1_out="$(eval_fixture "$pos1_json" "$NFM_FIXTURE_FILE")"
assert_symmetric "P1: service→external" "$pos1_out"

# ═══════════════════════════════════════════════════════════════
# Positive case 2: bidirectional=true triggers symmetric regardless of trafficType
# ═══════════════════════════════════════════════════════════════
echo "=== Positive 2: bidirectional=true triggers symmetric regardless of trafficType ==="
pos2_json='{"communicationContract":{"allowedRelations":[{"id":"bidir-stream","action":"allow","from":{"kind":"service","name":"media"},"to":{"kind":"service","name":"storage"},"trafficType":"streaming","bidirectional":true}]}}'
pos2_out="$(eval_fixture "$pos2_json" "$NFM_FIXTURE_FILE")"
assert_symmetric "P2: bidirectional triggers symmetric" "$pos2_out"

# ═══════════════════════════════════════════════════════════════
# Positive case 3: trafficType != "any" without bidirectional → symmetric (D18-NEW)
# ═══════════════════════════════════════════════════════════════
echo "=== Positive 3: trafficType != \"any\" without bidirectional → symmetric (D18-NEW) ==="
pos3_json='{"communicationContract":{"allowedRelations":[{"id":"streaming-no-bidir","action":"allow","from":{"kind":"service","name":"media"},"to":{"kind":"service","name":"storage"},"trafficType":"streaming"}]}}'
pos3_out="$(eval_fixture "$pos3_json" "$NFM_FIXTURE_FILE")"
assert_symmetric "P3: streaming without bidirectional" "$pos3_out"

# ═══════════════════════════════════════════════════════════════
# Seeded negative 1: local tenant-to-tenant shall NOT get symmetric
# (FS-620 L729: client isolation includes reverse initiation denial)
# (FS-640 L749: receiver-to-controller initiation denied unless explicitly modeled)
# ═══════════════════════════════════════════════════════════════
echo "=== Seeded negative 1: local tenant-to-tenant → one-way (no symmetric injection) ==="
neg1_json='{"communicationContract":{"allowedRelations":[{"id":"tenant-to-tenant","action":"allow","from":{"kind":"tenant-set","name":"cameras"},"to":{"kind":"tenant-set","name":"recorders"},"trafficType":"any"}]}}'
neg1_out="$(eval_fixture "$neg1_json" "$NFM_FIXTURE_FILE")"
assert_no_returnBehavior "N1: tenant-to-tenant one-way" "$neg1_out"

# ═══════════════════════════════════════════════════════════════
# Seeded negative 2: explicit returnBehavior preserved verbatim
# (FS-180 L206-212: return behavior is a required field; explicit wins)
# ═══════════════════════════════════════════════════════════════
echo "=== Seeded negative 2: explicit returnBehavior=\"one-way\" preserved ==="
neg2_json='{"communicationContract":{"allowedRelations":[{"id":"explicit-one-way","action":"allow","from":{"kind":"service","name":"media"},"to":{"kind":"external","uplinks":["wan"]},"trafficType":"any","returnBehavior":"one-way"}]}}'
neg2_out="$(eval_fixture "$neg2_json" "$NFM_FIXTURE_FILE")"
assert_returnBehavior_equals "N2: explicit returnBehavior preserved" "$neg2_out" "one-way"

# Also verify explicit returnBehavior="symmetric" is preserved (not stripped)
echo "=== Seeded negative 2b: explicit returnBehavior=\"symmetric\" preserved ==="
neg2b_json='{"communicationContract":{"allowedRelations":[{"id":"explicit-symmetric","action":"allow","from":{"kind":"service","name":"media"},"to":{"kind":"external","uplinks":["wan"]},"trafficType":"any","returnBehavior":"symmetric"}]}}'
neg2b_out="$(eval_fixture "$neg2b_json" "$NFM_FIXTURE_FILE")"
assert_returnBehavior_equals "N2b: explicit symmetric preserved" "$neg2b_out" "symmetric"

# ═══════════════════════════════════════════════════════════════
# Seeded negative 3: local tenant-to-tenant with bidirectional → no symmetric
# (FS-640 tenant-set exclusion must apply in bidirectional path too)
# ═══════════════════════════════════════════════════════════════
echo "=== Seeded negative 3: local tenant-to-tenant with bidirectional → one-way (no symmetric injection) ==="
neg3_json='{"communicationContract":{"allowedRelations":[{"id":"tenant-to-tenant-bidir","action":"allow","from":{"kind":"tenant-set","name":"cameras"},"to":{"kind":"tenant-set","name":"recorders"},"trafficType":"streaming","bidirectional":true}]}}'
neg3_out="$(eval_fixture "$neg3_json" "$NFM_FIXTURE_FILE")"
assert_no_returnBehavior "N3: tenant-to-tenant bidirectional" "$neg3_out"

pass_timed "FS-640-HDS-010-SDS-010-SMS-060-nfm-returnBehavior-injection-scoping" "${start_ms}"
