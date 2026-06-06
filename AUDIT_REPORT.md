# Shwouns Smart Contract Security Review

**Review date:** June 6, 2026  
**Commit reviewed:** `8c1ac0c888ad974b1b1ed0cfd004f6fe14648356`  
**Reviewer:** OpenAI Codex  
**Status:** Pre-deployment review

## Executive Summary

The review identified **3 critical, 3 high, 6 medium, and 2 low severity findings**.
The most serious issues invalidate the intended per-proposal fund-isolation guarantee:

- `finalize()` can be reentered, executing an approved payment multiple times against funds
  collected for other proposals.
- Arbitrary proposal calls can approve or otherwise expose the DAO's commingled token balances,
  bypassing the per-proposal ledger.
- Anyone can activate vaults for nonexistent token IDs, growing the active set until proposal
  queueing exceeds the block gas limit.

The documented production deployment command also currently reverts because the script relies on
the ephemeral Foundry script contract's `address(this)`.

**Recommendation:** Do not deploy until all Critical and High findings are fixed and the fixes
receive a focused follow-up review.

## Scope

Reviewed production code under:

- `src/governance/`
- `src/vault/`
- `src/rewards/`
- `src/auction/`
- `src/token/`
- `script/`

Forked Nouns/Tokenbound libraries marked pristine were reviewed primarily at their integration
boundaries. This was a source review with Foundry PoCs, not a formal verification engagement.

## Verification

- Baseline: **129 tests passed**
- Audit PoCs: **7 exploit/accounting tests passed**
- Full audit harness: **13 tests passed**
- Deployment simulation: **failed**, reproducing H-02

PoCs are in `test/audit/AuditFindings.t.sol`.

## Findings Summary

| ID | Severity | Title |
|---|---|---|
| C-01 | Critical | Reentrant finalization spends funds reserved for another proposal |
| C-02 | Critical | Arbitrary proposal calls bypass the per-proposal ERC-20 ledger |
| C-03 | Critical | Nonexistent token vaults can permanently DoS governance queueing |
| H-01 | High | Cancel or veto after partial collection permanently strands funds |
| H-02 | High | The production deployment script cannot run |
| H-03 | High | One approved GI NFT can authorize every voter sequentially |
| M-01 | Medium | Reward pools are overallocated and can become insolvent |
| M-02 | Medium | ERC-20-funded vaults can disappear from the active set |
| M-03 | Medium | Stuck-proposal refunds reward non-contributors and can omit assets |
| M-04 | Medium | ERC-20 accounting assumes exact, successful transfers |
| M-05 | Medium | Lifecycle loops become uncallable as the vault set grows |
| M-06 | Medium | `lockParts()` can be bypassed through the Art descriptor handoff |
| L-01 | Low | Malformed ERC-1271 signatures revert instead of returning invalid |
| L-02 | Low | Excess top-ups become untracked and stranded |

## Critical Findings

### C-01: Reentrant finalization spends funds reserved for another proposal

**Affected:** `ShwounsDAOProposals.sol:651-680`

`finalize()` performs arbitrary external calls before setting `finalized` and `executed`. A target
receiving ETH can reenter `finalize(proposalId)`. The inner invocation sees the proposal as
`Collected` and executes the same actions again.

Because all ETH is physically commingled in DAOLogic, the second payment can consume ETH whose
ledger belongs to another proposal. The victim proposal then passes its ledger check but cannot
fund its call.

**PoC:** `test_audit_finalizeReentrancySpendsAnotherProposalsETH`

**Recommendation:** Add a per-proposal execution lock and apply checks-effects-interactions. Mark
the proposal executing before external calls, while preserving retryability by allowing the whole
transaction to roll back on failure.

### C-02: Arbitrary proposal calls bypass the per-proposal ERC-20 ledger

**Affected:** `ShwounsDAOProposals.sol:657-680`

The ledger validates requested assets, but proposal actions execute as unrestricted calls from the
DAO. A zero-funding proposal can call `token.approve(attacker, max)`. The attacker can then
`transferFrom` ERC-20 balances collected for unrelated proposals.

This remains exploitable even after adding a reentrancy guard because the accounting ledger does
not constrain allowances or arbitrary side effects.

**PoC:** `test_audit_approvalActionDrainsAnotherProposalsERC20`

**Recommendation:** Do not custody concurrent proposal funds in one unrestricted executor.
Use isolated per-proposal escrow contracts/accounts, and execute each proposal only from its own
escrow. Balance-based bookkeeping in a shared arbitrary-call wallet is not enforceable isolation.

### C-03: Nonexistent token vaults can permanently DoS governance queueing

**Affected:** `ShwounsVaultRegistry.sol:112-149`,
`ShwounsDAOProposals.sol:439-455`

`createVaultFor()` accepts any token ID, and `markActive()` verifies only that the caller has the
deterministic vault address. An attacker can deploy vaults for nonexistent token IDs and send each
one wei, adding unlimited entries to `_activeVaults`.

`queue()` copies the entire active set into storage in one transaction. Once the attacker adds
enough fake vaults, every funding proposal exceeds the block gas limit. The set cannot be cleaned
through normal owner withdrawals because nonexistent tokens have no owner.

**PoC:** `test_audit_nonexistentTokenVaultCanPolluteActiveSet`

**Recommendation:** Require that the bound token exists before vault creation and activation.
Also redesign queue-time freezing as a paginated process with bounded work per transaction.

## High Findings

### H-01: Cancel or veto after partial collection permanently strands funds

**Affected:** `ShwounsDAOProposals.sol:384-423`, `1078-1118`

The proposer or signer may cancel while a proposal is `Snapshotted` and partially collected.
`state()` then returns `Canceled`, preventing further collection, finalization, and
`refundStuckProposal()`, which accepts only `Collected`.

The vetoer can produce the same result after partial or complete collection.

**PoC:** `test_audit_cancelAfterPartialCollectPermanentlyStrandsFunds`

**Recommendation:** Disallow cancel/veto after the first successful pull, or transition canceled
and vetoed funded proposals into a recoverable refund state.

### H-02: The production deployment script cannot run

**Affected:** `Deploy.s.sol:179-181`, `259-264`, `334-340`

The production path uses the ephemeral script contract's `address(this)` as Art descriptor and DAO
admin. Foundry rejects this during script simulation:

`Usage of address(this) detected in script contract. Script contracts are ephemeral`

The documented `forge script ... --broadcast` flow therefore cannot deploy the system.

**Reproduction:** `forge script script/Deploy.s.sol -vvv`

**Recommendation:** Use the broadcaster/admin EOA or an explicitly deployed, persistent deployment
coordinator. Add a forked or Anvil broadcast rehearsal test that follows the exact runbook.

### H-03: One approved GI NFT can authorize every voter sequentially

**Affected:** `GovernanceRewards.sol:183-203`, `ApprovalRegistry.sol:61-69`

Eligibility checks only current GI NFT ownership, while claims are tracked by voter address.
After one voter claims, the approved NFT can be transferred to the next voter, who can also claim.
One approved token can therefore unlock rewards for every participating address.

**PoC:** `test_audit_oneApprovedGINFTCanAuthorizeMultipleVoterClaims`

**Recommendation:** Bind eligibility at vote time or proposal snapshot, and/or track
`claimedByTokenId[proposalId][giTokenId]`. If transferable eligibility is intentional, do not
describe the mechanism as an anti-Sybil or identity gate.

## Medium Findings

### M-01: Reward pools are overallocated and can become insolvent

`allocateProposalReward()` uses the raw ETH balance without subtracting existing allocations.
Gas refunds and owner sweeps also spend the same balance. Multiple proposal pools can exceed
available ETH, making later valid claims revert.

**PoC:** `test_audit_rewardPoolsCanBeAllocatedBeyondContractBalance`

Track total reserved and claimed amounts. Limit gas refunds and sweeps to unreserved ETH.

### M-02: ERC-20-funded vaults can disappear from the active set

`markPossiblyInactive()` removes a vault whenever its ETH balance is zero, without checking ERC-20
balances. An owner can call `withdrawERC20(..., 0)` and remove a fully funded ERC-20 vault.

**PoC:** `test_audit_zeroERC20WithdrawalRemovesFundedVaultFromActiveSet`

The registry cannot generically enumerate ERC-20 holdings. Track assets explicitly or use an
owner-independent participation mechanism that does not infer activity from ETH balance.

### M-03: Stuck-proposal refunds reward non-contributors and can omit assets

Refunds distribute actual collected funds according to snapshot balances, not amounts actually
pulled from each vault. A vault drained before collection can receive a refund funded by other
vaults. The admin may also omit an asset from `assetsToRefund`, after which the proposal is marked
finalized and the omitted funds remain stranded.

Track per-vault collected amounts and refund those amounts. Require the complete asset set or make
refund completion paginated and asset-aware.

### M-04: ERC-20 accounting assumes exact, successful transfers

Collection increments the ledger by the requested transfer amount rather than the DAO's balance
increase. Fee-on-transfer tokens therefore overstate collection. `topUp()` and refund paths use raw
`transferFrom`/`transfer` without checking returned booleans.

Use `SafeERC20` and balance deltas. Explicitly reject unsupported rebasing or fee-on-transfer assets
if exact accounting is required.

### M-05: Lifecycle loops become uncallable as the vault set grows

`queue()` copies the complete active set in one call, and `refundStuckProposal()` contains a nested
asset-by-vault loop. Even without C-03's malicious inflation, normal growth can exceed block gas.

Make freezing and refunds paginated with explicit progress state and bounded batch sizes.

### M-06: `lockParts()` can be bypassed through the Art descriptor handoff

After `lockParts()`, the Descriptor owner can still call `setArtDescriptor()`, transferring direct
Art mutation authority to another address. That address can then change palettes and trait pages
without passing the Descriptor's lock.

Apply `whenPartsNotLocked` to authority-changing Art operations or permanently lock the Art
descriptor when parts are finalized.

## Low Findings

### L-01: Malformed ERC-1271 signatures revert instead of returning invalid

`ShwounsVault._isValidSignature()` reads `signature[64]` and dynamic offsets without validating
lengths. Malformed input reverts, which can break integrations expecting ERC-1271's invalid magic
value.

Validate signature length and offsets before slicing.

### L-02: Excess top-ups become untracked and stranded

`topUp()` accepts amounts greater than the outstanding requirement. Finalization spends only the
approved action amount, leaving the excess in DAOLogic without refund attribution.

Cap top-ups at `requestedAmount - collected`, or record and return excess to the contributor.

## Positive Observations

- Vault `pullProRata()` correctly resolves the locked DAO address at call time.
- The implementation deliberately excludes Tokenbound's selector override mechanism.
- Vote checkpoints and signed-proposal domain separation follow established patterns.
- Existing tests cover the happy path and several previously discovered lifecycle failures well.
- Storage layout inspection showed no immediate overlap in the current DAO implementation.

## Remediation Order

1. Replace shared DAO custody with per-proposal escrow and add finalization reentrancy protection.
2. Restrict vault activation to existing Shwouns and paginate active-set freezing.
3. Make cancel/veto recovery-safe.
4. Repair and rehearse the deployment script.
5. Redesign GI eligibility and reward reservations.
6. Address ERC-20 accounting, refund correctness, and remaining medium/low findings.

