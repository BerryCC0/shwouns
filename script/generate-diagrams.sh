#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/docs/architecture/diagrams"
TMP="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP"
}
trap cleanup EXIT

for tool in forge surya sol2uml dot; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "error: required command not found: $tool" >&2
    exit 1
  fi
done

mkdir -p "$OUT"

# Flattening gives Surya and sol2uml the inherited OpenZeppelin contracts that
# they cannot resolve from Foundry remappings on their own.
forge flatten "$ROOT/src/governance/ShwounsDAOLogic.sol" -o "$TMP/ShwounsDAOLogic.sol"
forge flatten "$ROOT/src/auction/ShwounsAuctionHouse.sol" -o "$TMP/ShwounsAuctionHouse.sol"

# Keep the call graph at contract granularity. A function-level graph of the
# complete flattened governance surface is too large to be useful.
surya graph --simple "$TMP/ShwounsDAOLogic.sol" |
  dot -Tsvg -o "$OUT/call-graph.svg"

sol2uml storage "$TMP/ShwounsDAOLogic.sol" \
  -c ShwounsDAOLogic \
  -o "$OUT/storage-ShwounsDAOLogic.svg"

sol2uml storage "$TMP/ShwounsAuctionHouse.sol" \
  -c ShwounsAuctionHouse \
  -o "$OUT/storage-ShwounsAuctionHouse.svg"

echo "Generated call graph and storage diagrams in $OUT"
