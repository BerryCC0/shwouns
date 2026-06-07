#!/usr/bin/env bash
# Anvil --broadcast deploy rehearsal (audit plan-review F4): the gate that proves DEPLOYABILITY, not
# just simulation. `forge script` alone passed a prior round yet the system was undeployable, so this
# runs the FULL runbook (deploy → load minimal art → lockParts → finalizeBootstrap) against a local
# anvil as REAL transactions, exercising CREATE2, library link-patching, the operator gate, and the
# atomic handoff with on-chain receipts. Then it asserts every broadcast tx succeeded and the deployed
# role-holders are DAO-owned with code on-chain.
#
# Requires: anvil + forge + cast on PATH (foundry). Usage: ./script/rehearse-deploy.sh
set -euo pipefail
export PATH="$HOME/.foundry/bin:$PATH"

RPC="http://127.0.0.1:8545"
REGISTRY="0x000000006551c19487814612e58FE06813775758"
# anvil default account #0 (well-known dev key; local-only).
KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
OUT="/tmp/shwouns-rehearse"
mkdir -p "$OUT"

echo "==> starting anvil"
anvil --silent --port 8545 > "$OUT/anvil.log" 2>&1 &
ANVIL_PID=$!
cleanup() { kill "$ANVIL_PID" 2>/dev/null || true; }
trap cleanup EXIT

# wait for anvil
for i in $(seq 1 30); do
  if cast block-number --rpc-url "$RPC" >/dev/null 2>&1; then break; fi
  sleep 0.5
done
cast block-number --rpc-url "$RPC" >/dev/null

echo "==> etching canonical ERC-6551 registry at $REGISTRY"
REG_CODE="$(forge inspect ERC6551Registry deployedBytecode)"
cast rpc anvil_setCode "$REGISTRY" "$REG_CODE" --rpc-url "$RPC" >/dev/null
REG_LEN="$(cast code "$REGISTRY" --rpc-url "$RPC" | wc -c | tr -d ' ')"
echo "    registry code length (hex chars): $REG_LEN"
[ "$REG_LEN" -gt 2 ] || { echo "ERROR: registry not etched"; exit 1; }

# Mine past block 0 so the seeder's blockhash(block.number - 1) doesn't underflow during the
# script's simulation fork (foundry's test EVM defaults to block 1; a fresh anvil starts at 0).
cast rpc anvil_mine 0x5 --rpc-url "$RPC" >/dev/null
echo "    mined to block $(cast block-number --rpc-url "$RPC")"

echo "==> broadcasting full deploy runbook"
if ! forge script script/RehearseDeploy.s.sol:RehearseDeploy \
      --rpc-url "$RPC" --broadcast --private-key "$KEY" --slow > "$OUT/run.log" 2>&1; then
  echo "ERROR: rehearsal script failed:"; tail -40 "$OUT/run.log"; exit 1
fi
grep -qE "ran successfully" "$OUT/run.log" && echo "    script ran successfully (sim requires passed)"

echo "==> verifying broadcast receipts"
BCAST="broadcast/RehearseDeploy.s.sol/31337/run-latest.json"
[ -f "$BCAST" ] || { echo "ERROR: no broadcast artifact at $BCAST"; exit 1; }
python3 - "$BCAST" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
receipts = d.get("receipts", [])
txs = d.get("transactions", [])
if not receipts:
    print("ERROR: no receipts in broadcast artifact"); sys.exit(1)
bad = [r for r in receipts if r.get("status") not in ("0x1", 1)]
total_gas = sum(int(r.get("gasUsed", "0x0"), 16) for r in receipts)
creates = sum(1 for t in txs if (t.get("transactionType") == "CREATE" or t.get("contractAddress")))
print(f"    transactions: {len(txs)}  receipts: {len(receipts)}  CREATEs: {creates}  total gas: {total_gas:,}")
# every step must be within the block gas limit (anvil default 30M).
over = [int(r.get("gasUsed","0x0"),16) for r in receipts if int(r.get("gasUsed","0x0"),16) > 30_000_000]
if bad:
    print(f"ERROR: {len(bad)} broadcast tx(s) did NOT succeed"); sys.exit(1)
if over:
    print(f"ERROR: {len(over)} tx(s) exceeded the 30M block gas limit"); sys.exit(1)
print("    all broadcast transactions succeeded, each within the block gas limit")
PY

echo "==> rehearsal OK: full deploy + art + finalize broadcast cleanly on anvil"
