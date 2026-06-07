# Shwouns — Nouns DAO fork with distributed vaults

Ethereum mainnet Nouns-style DAO with a fundamentally different economic model: per-Noun
ERC-6551 vaults instead of a central treasury. Built from `nouns-monorepo @ main` plus
Tokenbound's ERC-6551 stack.

## What's distinctive vs mainline Nouns

- **No central treasury.** Each Shwoun gets an ERC-6551 token-bound account ("Vault") on
  mint, owned by the current holder. Vault owner can deposit/withdraw ETH or any ERC-20
  at will. The vault can also act as a smart-contract wallet for DeFi (yield strategies,
  bridges) via the `Permissioned` delegation pattern.
- **Governor pulls pro-rata from vaults at execution**, not from a timelock. Snapshot
  happens at queue (after vote passes). Caller withdraws during queue→execute reduce
  the proposal's funding. Shortfalls are accepted.
- **Auction proceeds fund voter incentives**, not the treasury. 100% of winning bid →
  `GovernanceRewards` contract. No-bid Shwouns mint to `GovernanceRewards` (not burned,
  not treasury-routed).
- **Governance Incentives NFT** (open paid mint, 0.01 ETH default) + DAO-approved
  allowlist gates who can earn voting incentives. For/Against votes earn rewards; Abstain
  does not. Refundable votes route gas refunds through GR.
- **Art = Nouns without noggles.** Fork of `NounsDescriptorV3` strips the glasses trait.
  Seeder generates 4-trait seeds (background, body, accessory, head). On mainnet deploy,
  art bytes are reused from Nouns' deployed `NounsArt` via SSTORE2 pointer sharing —
  cheap (~$50 in gas), CC0-clean.

## Architecture (18 production contracts)

```
Token layer:        ShwounsToken, ShwounsSeeder, ShwounsDescriptor, ShwounsArt,
                    Inflator, SVGRenderer
Vault layer:        ShwounsVault (ERC-6551 impl), ShwounsVaultRegistry (active-set + DAO ref)
Auction layer:      ShwounsAuctionHouse (UUPS proxy, V3-fork)
Governance layer:   ShwounsDAOLogic (UUPS facade), ShwounsDAOProposals (library —
                    propose/vote/state/queue→collect→finalize + dynamic-quorum compute),
                    ShwounsDAOSignatures (library — EIP-712 signed proposals + editing),
                    ShwounsDAOQuorum (library — dynamic-quorum checkpoint admin),
                    ShwounsDAOData (candidates), GovernanceAuthRegistry, GovernedOwnable
Rewards layer:      GovernanceRewards, GovernanceIncentivesNFT, ApprovalRegistry
Execution layer:    ProposalEscrow (per-proposal EIP-1167 clone)
Deployment helper:  Bootstrap (generic operator-gated CREATE2 coordinator), ShwounsDeployer
                    (library — shared deploy orchestration + library link-patching),
                    Deploy.s.sol, CopyArtFromNouns.s.sol
```

> The governance library is split across three libraries (ShwounsDAOProposals /
> ShwounsDAOSignatures / ShwounsDAOQuorum) and `via_ir = true` so the facade + each library fit
> under EIP-170. The HOT paths (propose/vote/state + the dynamic-quorum compute) stay in
> ShwounsDAOProposals as same-library JUMPs; the cold sig/editing + quorum-admin paths delegatecall.

## Proposal lifecycle (the novel mechanic)

```
propose → vote → queue
                   ↓
            recordSnapshot(proposalId, batchSize)    [paged across active vaults]
                   ↓
            collect(proposalId, vaultIds[])           [paged; pulls pro-rata to DAOLogic]
                   ↓
            finalize(proposalId)                      [one-shot; makes target.call(s)]
                   ↓
            GR.allocateProposalReward(proposalId)     [auto-called inside finalize]
                   ↓
            voter.claimVotingReward(pid, giTokenId)   [lazy, per-voter claim]
```

For/Against voters with an approved Governance Incentives NFT claim a pro-rata share
of the proposal's reward pool (0.1 ETH default). Abstain voters don't earn.

## Key invariants

- **`ShwounsVault.pullProRata` is callable ONLY by the currently-registered DAOLogic.**
  Looked up via `vaultRegistry.daoLogic()` (locked once at deployment).
- **Vault impl is non-upgradeable** (deliberate — closes the Tokenbound upgrade vector).
  Implementation address pinned in `VaultRegistry.vaultImplementation` (locked).
- **Vaults must never use `Overridable`** — that was Tokenbound's feature where a Noun
  owner could override any function selector, including `pullProRata`. We stripped it.
- **DAOLogic.execute is replaced** — no timelock. Funds flow via snapshot→collect→finalize.
- **`finalize()` is retryable** — if `target.call` reverts, funds stay in DAOLogic; caller
  can re-run finalize after conditions change. Stuck-fund recovery via `refundStuckProposal`.
- **GI NFT eligibility is tokenId-keyed**, not address-keyed. Approval follows the NFT
  on transfer. This is intentional — DAO approves a specific (auditable) identity-bound
  asset.

## Deployment

The deployer EOA becomes the Bootstrap `operator` (the only address that can drive it); all protocol
roles are held by the persistent Bootstrap until `finalizeBootstrap`, then atomically handed to the
DAO. No `new X()` embedded code — ShwounsDeployer reads creation bytecode from artifacts (`vm.getCode`)
and link-patches the libraries, so it requires the built artifacts on disk.

```bash
# 1. Deploy + wire everything via Bootstrap (deploy-only: paused, all roles with Bootstrap).
FOUNDERS_DAO=0x...  \
  forge script script/Deploy.s.sol --rpc-url $MAINNET_RPC --broadcast --verify
#    → note the Bootstrap address (b) and manifest (m.descriptor) from the run output.

# 2. Copy Nouns art via SSTORE2 pointer sharing (~$50), routed through Bootstrap (it owns the
#    descriptor). One executeBatch tx.
SHWOUNS_BOOTSTRAP=$BOOTSTRAP  SHWOUNS_DESCRIPTOR=$DESCRIPTOR  \
  forge script script/CopyArtFromNouns.s.sol --rpc-url $MAINNET_RPC --broadcast

# 3. Lock parts when art is final (operator → Bootstrap → descriptor).
cast send $BOOTSTRAP 'execute(address,bytes)' $DESCRIPTOR $(cast calldata 'lockParts()')

# 4. One-shot atomic handoff: validates all wiring/locks/immutables, binds the registry, unpauses
#    (kicks off auction #1), transfers every Ownable to the DAO, sets DAO admin. Reverts if any
#    precheck fails (never a silent bad handoff). Permanently disables Bootstrap.
cast send $BOOTSTRAP finalizeBootstrap
```

Rehearse the whole runbook locally first: `./script/rehearse-deploy.sh` (anvil + minimal art).

For **testnet** (Sepolia, etc.) deployments, Nouns Art isn't deployed there, so
`CopyArtFromNouns` won't work. Options:
- Re-encode and re-upload from Nouns' source PNGs using the `nouns-assets` NPM package
- Skip art entirely for testnet (token URIs will revert; that's fine if you're testing
  governance/auction flows only)

## Build & test

```bash
forge build --sizes          # via_ir; verify EVERY contract < 24,576 (EIP-170 gate, audit F1)
forge test                   # 212 tests across 26 suites
forge test -vvv              # with trace output
./script/check-storage-layout.sh   # nested storage-layout drift gate (audit F5)
./script/rehearse-deploy.sh        # anvil --broadcast full deploy rehearsal (audit plan-review F4)
```

> `via_ir = true` is required (the facade doesn't fit EIP-170 otherwise — optimizer_runs bottomed at
> ~207 bytes over even at runs=1). `forge build` (no `--sizes`) does NOT enforce EIP-170 — always use
> `--sizes`. via_ir treats `block.timestamp`/`block.number` as tx-invariant (correct for prod), so
> tests must not `vm.warp`/`vm.roll` mid-function and then re-read them in a loop.

Forge is at `~/.foundry/bin/forge` (may or may not be in PATH depending on session env;
user-level `~/.claude/settings.json` adds it to PATH for future Claude Code sessions).

## File authority

| Files | Source | Safe to edit? |
|-------|--------|--------------|
| `src/vault/abstract/*`, `src/vault/lib/*` | Forked Tokenbound — pristine copies | Only with care; original audit trail value |
| `src/vault/erc6551/*` | ERC-6551 reference impl | No — match spec exactly |
| `src/libs/Inflate.sol`, `SSTORE2.sol`, `NFTDescriptorV2.sol` | Forked Nouns libs | No — battle-tested |
| `src/token/SVGRenderer.sol`, `Inflator.sol` | Forked Nouns | No (only `import` paths adapted) |
| `src/token/ShwounsArt.sol`, `ShwounsDescriptor.sol`, `ShwounsSeeder.sol`, `ShwounsToken.sol` | Forked Nouns — glasses removed | Yes |
| `src/auction/*`, `src/governance/*`, `src/rewards/*` | Original work | Yes |
| `*.original` files (in src/) | Pristine upstream references | No — used for audit diff comparison |
| `script/*.s.sol` | Deployment + ops scripts | Yes |
| `test/*` | Test suites | Yes |

## Plan + AVP record

The full architecture decisions + AVP verification trail is at
`~/.claude/plans/what-happens-to-a-lucky-meteor.md`. That file is the source of truth
for design rationale — read it before making non-obvious changes.

## What's NOT done

> **Status (June 2026):** A 3rd review (OpenAI Codex, `AUDIT_REPORT.md`, commit 8c1ac0c) found
> 14 findings (3C/3H/6M/2L) — all verified to reproduce. The **full security remediation is now
> IMPLEMENTED** on branch `security-remediation` per `REMEDIATION_PLAN.md` v6 +
> `ARCHITECTURE_REVIEW_A.md`: all 14 findings fixed across 8 phased commits; the 13 audit PoCs are
> flipped to assert safe behavior (permanent regressions); **204 tests pass**. Both UUPS proxies'
> storage layouts are **byte-identical to baseline** (`./script/check-storage-layout.sh`). Core of
> the fix: per-proposal `ProposalEscrow` clones execute all actions (closing the C-01/C-02 fund-
> isolation breaks), a `GovernanceAuthRegistry` + `GovernedOwnable` authenticate the active escrow,
> append-only active set + paged queue-freeze, contribution-based refunds, reservation-accounted
> rewards, and a persistent `Bootstrap` coordinator with a one-shot no-permanent-EOA handoff.
> **Do NOT deploy** until the focused post-implementation audit (the gate the plan mandates).
>
> _(Earlier: the correctness gate + V4 parity landed on `governance-parity-and-lifecycle-fixes`,
> which `security-remediation` builds on. See `~/.claude/plans/hey-claude-we-ve-been-velvet-canyon.md`.)_
>
> **Round 2 (June 2026):** A focused post-implementation audit found **5 findings (4 blockers + 1
> medium)** — the protocol logic was sound but the system was undeployable + insecure to deploy + had
> a DoS-able refund. ALL FIXED on `security-remediation` (plan
> `~/.claude/plans/audit-findings-critical-deployment-reactive-bachman.md`): **F1** EIP-170 — split
> the governance library into ShwounsDAOProposals/Signatures/Quorum + `via_ir` (Bootstrap 143KB→16KB;
> every contract now < 24,576, gated by `forge build --sizes`); **F2** front-running — generic
> operator-gated Bootstrap (CREATE2 deploy + execute + manifest + atomic finalize, no permissionless
> entry); **F3** art-loading — CopyArtFromNouns routes onlyOwner descriptor ops through
> `bootstrap.executeBatch`; **F4** refund DoS — refunds go to the vault (non-reverting receive), not a
> hostile NFT owner; **F5** storage gate — recursive nested-aware JSON diff that catches reorders
> inside `Storage`/`Proposal`/`SnapshotState`. **212 tests pass**, storage layout unchanged, and the
> full deploy+art+finalize runbook broadcasts cleanly on anvil (`./script/rehearse-deploy.sh`, 41 txs).
> **Do NOT deploy** until a focused RE-review of the Bootstrap rewrite + the refund-recipient change
> (the new attack surface this round introduced).

- **Focused re-review (the gate)** — review the generic CREATE2 Bootstrap + ShwounsDeployer link-
  patching + the refund-to-vault change before any Sepolia/mainnet deploy.
- **Remaining V4 parity** — admin param bounds + `initialize` validation (needs migrating tests off
  votingPeriod=5 / threshold=0), dynamic-quorum seed-at-init, proposal editing (Updatable +
  `queueDeadline`/`Expired`), bulk `proposals()` getter, and a mechanical ABI parity checklist.
- **External audit** — recommended firms: Spearbit, Code4rena, Cantina. Budget $5-15k,
  2-4 weeks lead time. Snapshot+collect+finalize mechanic is novel and warrants focused
  review.
- **Sepolia dress rehearsal** — the anvil rehearsal passes; a real-RPC Sepolia run (re-encoding art,
  since Nouns Art isn't on testnet) is still worth doing before mainnet.
- **Production deploy** — half a day once audit feedback is incorporated.
- **Brand call** — token name/symbol use "Shwouns"/"SHWN". Final branding (logo, site,
  social handles) is product-side work, not protocol.
