# Shwouns Documentation

Shwouns is a Nouns DAO fork with **no central treasury**: capital lives in per-Noun ERC-6551 vaults
the holder controls, and governance pulls pro-rata from those vaults at execution. New here? Start
with **[overview.md](overview.md)**.

This is the **curated** documentation set (hand-written, GitHub-rendered Markdown with Mermaid
diagrams). It cross-links to the **generated API reference** under [reference/](reference/SUMMARY.md)
(produced by `forge doc` from the contracts' NatSpec). The two sets are intentionally separate and
cross-linked — they don't merge.

## Reading paths by audience

### 🔌 Integrators & app developers (primary)
1. [overview.md](overview.md) — what Shwouns is + the system map.
2. [flows/governance-lifecycle.md](flows/governance-lifecycle.md) — the propose→vote→queue→
   recordSnapshot→collect→finalize→claim sequence, the state machine, and the **events to index**.
3. [flows/auction-and-rewards.md](flows/auction-and-rewards.md) — auction, proceeds, and how voters
   claim incentives.
4. [reference/](reference/SUMMARY.md) — every contract and function (signatures, params, returns,
   events, errors) generated from NatSpec.

### 🔍 Auditors & security reviewers
1. [architecture/auth-and-trust.md](architecture/auth-and-trust.md) — principals, the
   executor-authentication chain, the key invariants, and residual trust.
2. [flows/escrow-execution.md](flows/escrow-execution.md) — the per-proposal escrow + `isActiveExecutor`
   (the C-01/C-02 fix; the novel core).
3. [architecture/storage-layout.md](architecture/storage-layout.md) — the UUPS layout discipline + the
   nested-aware drift gate.
4. Finding history: [`AUDIT_REPORT.md`](../AUDIT_REPORT.md), [`REMEDIATION_PLAN.md`](../REMEDIATION_PLAN.md),
   [`ARCHITECTURE_REVIEW_A.md`](../ARCHITECTURE_REVIEW_A.md).

### 🛠️ Contributors
1. [architecture/relationships.md](architecture/relationships.md) — who owns/calls/references whom +
   the **Forked components** origins (what we changed and why).
2. The **File authority** table in [CLAUDE.md](../CLAUDE.md) — which files are editable vs. forked
   (do-not-edit), and the build/test/gate commands.
3. [flows/deployment.md](flows/deployment.md) — the Bootstrap deploy + handoff and the script
   operational reference.

### 🏛️ DAO community & newcomers
1. [concepts/no-treasury-vaults.md](concepts/no-treasury-vaults.md) — per-Noun vaults vs. a treasury.
2. [concepts/voter-incentives.md](concepts/voter-incentives.md) — the GI NFT + allowlist + rewards.

## Map of this directory

```
docs/
  README.md                      ← you are here (index + reading paths)
  overview.md                    what Shwouns is; the system map
  concepts/                      community-facing intros
    no-treasury-vaults.md
    voter-incentives.md
  architecture/                  how it fits together
    relationships.md             ownership/call/reference map + Forked components
    auth-and-trust.md            authorization model + trust boundaries
    storage-layout.md            UUPS layout discipline + the drift gate
    diagrams/                    generated SVGs (surya / sol2uml) + Mermaid sources
  flows/                         step-by-step sequences (Mermaid)
    governance-lifecycle.md      propose → … → finalize → claim
    escrow-execution.md          per-proposal escrow + executor auth
    auction-and-rewards.md       auction → proceeds → voter rewards
    deployment.md                Bootstrap deploy/handoff + script reference
  reference/                     GENERATED API book (forge doc) — see SUMMARY.md
  storage-layout/                committed storage snapshots (the gate's baselines)
```

## Regenerating the docs

- **Generated reference** (after any NatSpec change): `forge doc` (writes to `docs/reference/`, per
  `foundry.toml [doc]`). The root [README.md](../README.md) is its homepage — keep it current.
- **NatSpec coverage gate**: `forge build` then `python3 script/check-natspec.py` (exit non-zero on
  gaps). Scope = Groups A + B (original work + forked-Nouns-with-glasses-removed); see the script
  header for the precise definition.
- **Diagrams**: see [architecture/diagrams/README.md](architecture/diagrams/README.md).

> **Status:** protocol logic complete, 212 tests passing, twice-remediated internally; **not deployed,
> not externally audited.** Mainnet is frozen pending a Sepolia rehearsal + external audit. The curated
> docs are derivable from the source + the repo-tracked review documents alone.
