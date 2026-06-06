#!/usr/bin/env bash
# §G storage-layout drift check (CI gate).
#
# The two UUPS proxies (ShwounsDAOLogic, ShwounsAuctionHouse) must keep a STABLE storage layout
# across changes — new governance state is appended into the dedicated struct gap (ShwounsDAOTypes
# .Storage.__gap), never by reordering or growing existing structs, and immutables (e.g.
# governanceAuth) live in bytecode, not storage. This script regenerates each proxy's layout and
# diffs it against the committed snapshot in docs/storage-layout/. Any difference fails CI.
#
# The committed snapshots were verified byte-identical to the pre-remediation baseline (commit
# 8c1ac0c) at every slot, so a passing check proves no existing slot — including inherited
# OpenZeppelin proxy storage — has shifted.
#
# Usage:  ./script/check-storage-layout.sh           (check)
#         ./script/check-storage-layout.sh --update   (regenerate snapshots after an intended change)
set -euo pipefail

FORGE="${FORGE:-forge}"
SNAP_DIR="docs/storage-layout"
CONTRACTS=(ShwounsDAOLogic ShwounsAuctionHouse)
MODE="${1:-check}"

"$FORGE" clean >/dev/null 2>&1 || true
fail=0
for c in "${CONTRACTS[@]}"; do
  cur="$("$FORGE" inspect "$c" storageLayout)"
  snap="$SNAP_DIR/$c.txt"
  if [[ "$MODE" == "--update" ]]; then
    printf '%s\n' "$cur" > "$snap"
    echo "updated $snap"
  else
    if ! diff -B <(printf '%s\n' "$cur") "$snap" >/dev/null; then
      echo "STORAGE LAYOUT DRIFT in $c:"
      diff -B <(printf '%s\n' "$cur") "$snap" || true
      fail=1
    else
      echo "OK: $c storage layout unchanged"
    fi
  fi
done
exit $fail
