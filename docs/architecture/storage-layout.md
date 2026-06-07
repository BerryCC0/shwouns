# Architecture: Storage layout & the upgrade-safety gate

The two UUPS proxies — `ShwounsDAOLogic` and `ShwounsAuctionHouse` — must keep a **stable storage
layout** across upgrades, or an upgrade would silently corrupt state. This page explains the
discipline and the CI gate that enforces it. The committed snapshots are
[`docs/storage-layout/*.norm.json`](.); the gate is `./script/check-storage-layout.sh`.

## Why it matters

A UUPS proxy keeps its storage and swaps its implementation. If a new implementation lays out storage
differently — reorders fields, grows a struct, inserts a variable — existing slots are reinterpreted
and state is corrupted. So every layout change must be **append-only into reserved space**, never a
reorder or an insert into existing structures.

## ShwounsDAOLogic — the single-struct + `__gap` pattern

All governance state lives in **one struct**, `ShwounsDAOTypes.Storage`, sitting at slot 0 of the
proxy, accessed by the libraries via `using … for Storage`. New fields are appended **inside that
struct, consuming its trailing `uint256[__gap]`**, and the gap is decremented by the number of slots
added. Critically, new fields go *inside* `Storage` (before the gap) — never after the `ds` field in
the contract — because inherited OpenZeppelin storage follows `ds`, and appending after it would shift
those inherited slots.

From `ShwounsDAOInterfaces.sol`, the gap has already absorbed several remediation additions:

```
uint256[46] __gap;   // was [50]; -4 for executing(1) + activeProposalId(1)
                     //                 + proposalEscrowImplementation+lock(1) + fundableAsset(1)
```

Two more append-only disciplines in the same struct/enum, both load-bearing for indexers **and** the
gate:

- **`SnapshotState` and `Proposal` fields are append-only.** Each remediation round appended fields
  (e.g. `frozenVaultIds`, `collected`, `freezeProgress`, `pulled`, `refundStarted/refunded`) with an
  explicit "append-only; do not reorder" comment. Reordering them would change the layout of the
  mappings'/structs' values.
- **The `ProposalState` enum is append-only.** `Updatable` (12) and `Executing` (13) were appended
  after the original states and must never be renumbered.

## Immutables don't touch proxy storage

The authorization plumbing (`GovernedOwnable.governanceAuth`, the auction house's `governanceAuth`,
the token/duration/WETH immutables) is `immutable` — it lives in contract **bytecode**, not storage.
That's why adding the auth registry reference to the governed contracts (including the upgradeable
auction house) added **no storage slot** and is invisible to the storage gate.

## The gate: nested-aware, not a flat table diff

`./script/check-storage-layout.sh` compares the current layout of each proxy against its committed
snapshot. It deliberately does **not** use a flat slot/offset table — that sees the proxy's `ds`
field as one opaque blob and would **miss a reorder inside** `Storage` / `Proposal` / `SnapshotState`
(audit F5). Instead it diffs the **complete reachable type graph**: every struct's member layout,
every mapping's key/value type, every array's base type and length.

- Source: `forge inspect <Contract> storageLayout --json`.
- Normalization: `script/normalize-storage-layout.py` strips only the churny compiler AST `id` from
  named types (so cosmetic recompiles don't cause spurious diffs) while **preserving array lengths**
  (so a `__gap` shrink — which must be matched by a real field addition — is caught), and it fails on
  any normalization collision.

```bash
./script/check-storage-layout.sh            # CI gate: compare against committed snapshots
./script/check-storage-layout.sh --update    # regenerate snapshots after an INTENDED change
```

> Run `--update` only when a layout change is deliberate and append-only, and review the snapshot diff
> carefully — the whole point is that an *un*intended layout change fails CI.

## Relationship to the NatSpec gate

This gate (`check-storage-layout.sh`) and the [NatSpec coverage gate](../../script/check-natspec.py)
are independent CI checks. NatSpec changes are comments only and never affect storage layout — but the
storage gate re-verifies that after the documentation pass, just as it does after any change. Both,
plus `forge build --sizes` (EIP-170) and `forge test`, are the green-bar set for this branch.

## Generated storage diagrams

When `sol2uml` is installed, `sol2uml storage` renders a visual slot map for each proxy under
[diagrams/](diagrams/) — a helpful companion to the JSON snapshots. Commands in
[diagrams/README.md](diagrams/README.md).
