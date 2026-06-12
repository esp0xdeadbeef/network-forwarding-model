#!/usr/bin/env bash
# GAMP-ID: TOOL-NFM-SEED-001
# GAMP-SCOPE: test infrastructure tool; idempotent fixture seeder
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: scripts/seed.sh --intent <path> [--inventory <path>] [--output <dir>]

  --intent <path>    Path to intent.nix (required)
  --inventory <path> Path to inventory.nix (optional)
  --output <dir>     Fixture output directory (default: tests/fixtures/seeded)
  --force            Recompile even if fixture exists
  --help             Show this help

The script compiles intent (and optionally inventory) through the full
compiler→NFM pipeline and caches the output as reusable test fixtures.

Output files:
  tests/fixtures/seeded/<intent-name>/compiled.json    Compiler output
  tests/fixtures/seeded/<intent-name>/forwarding.json  NFM output
  tests/fixtures/seeded/<intent-name>/manifest.txt     Source paths + timestamp

Exit codes:
  0  Fixture ready (fresh or cached)
  1  Compilation failed
  2  Invalid arguments
EOF
}

FORCE=false
INTENT=""
INVENTORY=""
OUTPUT_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --intent)   INTENT="$2"; shift 2 ;;
    --inventory) INVENTORY="$2"; shift 2 ;;
    --output)   OUTPUT_DIR="$2"; shift 2 ;;
    --force)    FORCE=true; shift ;;
    --help)     usage; exit 0 ;;
    *)          echo "Unknown flag: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ -z "$INTENT" ]]; then
  echo "ERROR: --intent is required" >&2
  usage
  exit 2
fi

if [[ ! -f "$INTENT" ]]; then
  echo "ERROR: intent file not found: $INTENT" >&2
  exit 2
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INTENT_NAME="$(basename "$(dirname "$INTENT")")"
OUTPUT_DIR="${OUTPUT_DIR:-${REPO_ROOT}/tests/fixtures/seeded/${INTENT_NAME}}"

MANIFEST="${OUTPUT_DIR}/manifest.txt"

# ── Idempotency check ──
if [[ "$FORCE" != "true" && -f "${OUTPUT_DIR}/compiled.json" && -f "${OUTPUT_DIR}/forwarding.json" ]]; then
  echo "seed: fixture exists at ${OUTPUT_DIR} (use --force to recompile)"
  exit 0
fi

mkdir -p "${OUTPUT_DIR}"

echo "seed: compiling ${INTENT} → ${OUTPUT_DIR}"
echo "seed: intent=$(realpath "${INTENT}")" > "${MANIFEST}"
echo "seed: started=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "${MANIFEST}"

# ── Compile through compiler → NFM ──
if ! nix run --no-write-lock-file "${REPO_ROOT}#compile-and-build-forwarding-model" \
     -- "${INTENT}" > "${OUTPUT_DIR}/forwarding.json"; then
  echo "seed: FAILED — compilation error" >&2
  echo "seed: status=failed" >> "${MANIFEST}"
  exit 1
fi

# ── Also run just the compiler for the compiled.json artifact ──
# Use nix flake archive to resolve the network-compiler path
ARCHIVE_JSON="$(mktemp)"
trap 'rm -f "${ARCHIVE_JSON}"' RETURN
nix flake archive --json "path:${REPO_ROOT}" > "${ARCHIVE_JSON}"
COMPILER_PATH="$(jq -er '.inputs["network-compiler"].path // empty' "${ARCHIVE_JSON}")"

if [[ -n "$COMPILER_PATH" ]]; then
  COMPILER_BIN="${COMPILER_PATH}#compile"
  # If inventory is provided, pass it; otherwise intent alone is enough for compiler
  if nix run --no-write-lock-file "path:${COMPILER_PATH}#compile" -- "${INTENT}" \
       > "${OUTPUT_DIR}/compiled.json" 2>/dev/null; then
    echo "seed: compiled.json from network-compiler"
  else
    echo "seed: compiled.json not available (compiler flake missing or failed)" >&2
    # Not fatal; forwarding.json is the primary artifact
  fi
else
  echo "seed: compiled.json not available (no network-compiler input in flake)" >&2
fi

echo "seed: completed=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "${MANIFEST}"
echo "seed: status=ok" >> "${MANIFEST}"
echo "seed: done — fixtures at ${OUTPUT_DIR}"
