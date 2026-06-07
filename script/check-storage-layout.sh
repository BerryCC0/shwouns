#!/usr/bin/env bash
# §G storage-layout drift check (CI gate) — recursive, nested-aware (audit F5).
#
# The two UUPS proxies (ShwounsDAOLogic, ShwounsAuctionHouse) must keep a STABLE storage layout:
# new governance state is appended into the dedicated struct gap (ShwounsDAOTypes.Storage.__gap),
# never by reordering or growing existing structs, and immutables (e.g. governanceAuth) live in
# bytecode, not storage.
#
# Unlike the old table diff (which saw the proxy's `ds` field as one opaque blob and so MISSED a
# reorder inside ShwounsDAOTypes.Storage / Proposal / SnapshotState), this diffs the COMPLETE
# reachable type graph: every struct's member layout, every mapping's key/value, every array's
# base + length. `forge inspect ... storageLayout --json` is normalized by
# normalize-storage-layout.py, which strips only the churny compiler AST id from named types
# (preserving array lengths, so a __gap shrink is caught) and fails on any normalization collision.
#
# Usage:  ./script/check-storage-layout.sh            (check against committed snapshots)
#         ./script/check-storage-layout.sh --update    (regenerate snapshots after an intended change)
set -euo pipefail

FORGE="${FORGE:-forge}"
PY="${PYTHON:-python3}"
SNAP_DIR="docs/storage-layout"
NORMALIZER="script/normalize-storage-layout.py"
CONTRACTS=(ShwounsDAOLogic ShwounsAuctionHouse)
MODE="${1:-check}"

mkdir -p "$SNAP_DIR"
fail=0
for c in "${CONTRACTS[@]}"; do
  cur="$("$FORGE" inspect "$c" storageLayout --json | "$PY" "$NORMALIZER")"
  snap="$SNAP_DIR/$c.norm.json"
  if [[ "$MODE" == "--update" ]]; then
    printf '%s\n' "$cur" > "$snap"
    echo "updated $snap"
  else
    if [[ ! -f "$snap" ]]; then
      echo "MISSING SNAPSHOT for $c ($snap) — run with --update"; fail=1; continue
    fi
    if ! diff -u "$snap" <(printf '%s\n' "$cur") >/dev/null; then
      echo "STORAGE LAYOUT DRIFT in $c:"
      diff -u "$snap" <(printf '%s\n' "$cur") || true
      fail=1
    else
      echo "OK: $c storage layout unchanged"
    fi
  fi
done
exit $fail
