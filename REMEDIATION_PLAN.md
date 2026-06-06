# Shwouns Security Remediation Plan

**For:** Codex security review (`AUDIT_REPORT.md`), commit `8c1ac0c`
**Status:** Plan only — no code changed yet. All 14 findings independently verified to reproduce
(13/13 PoCs in `test/audit/AuditFindings.t.sol` pass; deploy sim reverts as described).
**Revision:** v6 — five review rounds incorporated (see "Round-2…6 corrections" below). v1's "move-in
to the facade" idea for C-01/C-02 was **withdrawn** (leaks unknown output assets). **Option A (per-escrow
execution of all actions + authenticated execution path) is the selected design** (§A), trust model
on-chain via `Bootstrap` + one-shot `finalizeBootstrap`. Round 6 closed three remaining gaps: terminal
`Executed` is now set **after** `escrow.execute` returns (v5 wrongly set it before, which a reentrant
permissionless rescue could exploit mid-execution); `Bootstrap` is deployed **first** and itself deploys
the auth registry (resolving a binder circularity); and "no permanent EOA" is **structurally enforced
after handoff** (ownership/admin destinations limited to the DAO or zero — **Ian ratified structural
enforcement**, §A10.5). **Reviewer's standing verdict: the round-5 fixes are correct, but v5 was not
closed — finding 1 reopened the A4 hazard; resolve before drafting the approval review.** v6 resolves it.
**No open design decisions remain.** The dedicated §A architecture review (§G) remains the gate before code.
**Scope rule:** every fix must keep the 129 baseline tests green and convert each audit PoC from
"demonstrates bug" to "asserts safe behavior" (kept as permanent regressions).

---

## Round-2…6 corrections (what changed, and why)

**Round 2** (review of v1) found nine issues — eight conceded, one a severity nuance; it redesigned the
C-01/C-02 architecture. **Round 3** (review of v2's Option A) found nine more — all conceded after
verifying two against the code (GI-NFT proceeds wiring; the three ownership models). **Round 4** (review
of v3) found five more + ratified A10's trust model + settled the smaller choices — all conceded after
verifying the deployment order. **Round 5** (review of v4) found four more — all conceded; clone init,
rescue gating, immutable-vs-storage-diff, fail-open registry. **Round 6** (review of v5) found three more
(2 High, 1 Medium) — all conceded: v5's "set `executed` before calls" wording reopened the A4 hazard via
permissionless rescue; "no permanent EOA" wasn't enforced post-handoff; and registry-first/Bootstrap-binds
was circular. v6 resolves all three (finding 2's enforcement awaits Ian's ratification). The pattern
across rounds: each fix exposes the next boundary; the design is now converging on the execution/auth
core. Gate before code stays the dedicated §A architecture review (§G) + post-implementation audit.

| v1 claim | Verdict | Change in v2 |
|---|---|---|
| Move-in/execute-from-facade closes C-02 | **Wrong** | Arbitrary execution can drop an *unlisted* asset into the reused facade; the sweep can't enumerate it; a later proposal's lingering `approve` drains it. Switched to a per-proposal execution identity; **Option A selected** (§A). |
| `nonReentrant` via inheritance | **Unsafe on OZ 4.9.6** | OZ-upgradeable is 4.9.6 (sequential storage; `ReentrancyGuardUpgradeable` = `_status` + `uint256[49] __gap`). Use an explicit appended lock slot + CI storage-layout diff (§A, §G). |
| `address(this)` → `msg.sender` in deploy | **Breaks direct tests** | In `_deploy`, `art.setDescriptor` is called by the Deploy contract, not `msg.sender`; identities diverge. Pass authority explicitly; test path pranks it (§F). |
| Block cancel/veto after first pull | **Self-contradictory + undesirable** | Contradicted its own test and disables the emergency brake. Replaced with: allow cancel/veto pre-finalize; funded → refundable state (§C). |
| Delta-measure vault→escrow (fee tokens) | **Incomplete** | The second hop charges another fee. Reject fee-on-transfer/rebasing as fundable assets, documented; single-hop only under per-escrow execution (§A). |
| `totalReserved` for reward solvency | **Insufficient** | Also need decrementing `remainingRewardPool[pid]`, an enforced claim deadline, release-only-remainder, and **both** `voterClaimed` AND `claimedByTokenId` flags (§D). |
| Fake-vault PoC: deposit reverts | **Wrong** | Vault notifications are `try/catch`, so a registry revert is swallowed. Correct assertion: deposit succeeds, tokenId never enters the active set (§B / C-03). |
| Paged freeze (loose) | **Needs a fixed boundary** | Snapshot `freezeTarget = activeVaultsLength()` at queue, page `[0, freezeTarget)`; sound only if the set is append-only (M-02) and `recordSnapshot` is gated until freeze completes (§B / M-05). |
| ERC-1271 test asserts `0xffffffff` | **Over-specified** | Assert "non-magic value and no revert"; `bytes4(0)` is a valid failure too (§E / L-01). |

| v2 / Option A claim (round 3) | Verdict | Change in v3 |
|---|---|---|
| One inherited `GovernedByDAO` base | **Unsafe** | Storage-bearing base shifts the AuctionHouse proxy + doesn't fit `ds.admin`. Stateless lib + `_checkOwner()` overrides (immutable `daoLogic`) + DAOLogic modifier change (§A5). |
| Governed set complete | **Omits GI NFT** | `GovernanceIncentivesNFT` is owned by GR (proceeds via `owner()`), so escrows can't govern it. Decouple `proceedsRecipient`=GR from owner=governance (§A6). |
| Break-glass owner a "minor" open item | **Approval-gating** | A retained EOA could bypass governance/upgrade/sweep. Elevated: no permanent EOA; time-limited deploy admin + irreversible handoff (§A10). |
| "Single-use, never refilled" escrows | **Not enforceable** | Anyone can send to a known escrow address. Narrower invariant: no *protocol path* routes another proposal's assets into an old escrow (§A7). |
| `rescueFromEscrow` (sketch) | **Underspecified** | Must cover ETH/ERC-20/721/1155 as constrained transfers, never set executor auth, define multi-input allocation; external positions out of scope (§A8). |
| Reject fee/rebasing "by documentation" | **Needs enforcement** | Exact deltas at collect/topUp + pre-execution solvency recheck + fundable-asset allowlist (§A accounting). |
| `isActiveExecutor(address)` only | **Insufficient** | Store `activeProposalId`; verify executing-flag + deterministic address + codehash + executing≠executed (§A3). |
| Upgrade safety unstated | **Needs invariants** | Storage-compatible upgrades; old frame clears auth; test `upgradeToAndCall` overwrite attempts (§A9). |
| C-02 test "allowance moves 0" | **Wrong shape** | Standard ERC-20 `transferFrom` reverts on insufficient balance. Assert revert + victim escrow unchanged (§A tests). |

| v3 claim (round 4) | Verdict | Change in v4 |
|---|---|---|
| `immutable daoLogic` in governed contracts | **Impossible** | Governed contracts are built before the DAO proxy (Deploy step 6). A `GovernanceAuthRegistry` deployed first, immutable-referenced, DAO bound once (§A5). |
| A9 guarantees `upgradeToAndCall` can't alter the lock | **Unguaranteeable** | A malicious approved impl can overwrite any slot. Instead: self-upgrade must be the final action; old frame clears auth; malicious impls explicitly out of scope (§A9). |
| `EXPECTED_ESCROW_CODEHASH` (sketch) | **Underspecified** | Constructor immutables vary the runtime hash. Use identical-runtime EIP-1167 clones; identity via CREATE2 address (§A1, A3.4). |
| Residual recovery "ETH-denominated contribution" | **Needs an oracle** | Manipulable for ERC-20s. Fixed immutable governance sink = GR (§A8). |
| A10 "time-limited admin" | **Runbook ≠ on-chain** | Must expire on-chain: `Bootstrap` contract + one-shot `finalizeBootstrap()` atomically hands off and self-revokes; auction paused until then; DAOLogic admin set directly (two-step can't self-accept) (§A10, §F). |

| v4 claim (round 5) | Verdict | Change in v5 |
|---|---|---|
| Escrow clone construction | **Unspecified** | EIP-1167 clones take no ctor args. Impl-immutable `daoLogic`/`residualSink`, deployed after DAOLogic, **no initializer** (else clone-takeover) (§A2). |
| Permissionless `rescueFromEscrow` | **Theft vector** | Could sweep live funding pre-execution. **Strict terminal-state gate**: only after executed or refund-complete (§A8). |
| Immutable `governanceAuth` upgrade-safe | **Storage-diff blind spot** | Immutables aren't in storage layout; a new impl can silently repoint the registry. `_authorizeUpgrade` verifies candidate reports canonical registry; DAOLogic preserves `isActiveExecutor` ABI (§A9). |
| Registry binding/forwarding | **Must fail closed** | Only Bootstrap binds, once, to a nonzero deployed proxy; unbound/revert/malformed/zero → unauthorized (§A5). |

| v5 claim (round 6) | Verdict | Change in v6 |
|---|---|---|
| `executed` set before calls (CEI) + rescue gates on `executed` | **Reopens A4** | Reentrant rescue could sweep the live escrow mid-finalize. Distinct `Executing` status; terminal `Executed` set only after `escrow.execute` returns + auth cleared (§A3). |
| "No permanent EOA" holds after handoff | **Not preserved** | A proposal could `transferOwnership`/`setPendingAdmin` to an EOA. **RATIFIED: structural enforcement** — destinations restricted to DAO or zero; upgradeability compatible; malicious impls out of scope per A9 (§A10.5). |
| Registry deployed first, Bootstrap binds | **Circular** | Registry can't know a not-yet-deployed Bootstrap. Bootstrap deployed first, deploys the registry (binder known at construction) — §A5, §F. |

---

## Triage at a glance

| ID | Root-cause cluster | Phase | Effort |
|---|---|---|---|
| H-02 deploy script | Deploy tooling | 0 (unblock) | S |
| C-03 fake-vault DoS | Active-set design | 1 | M |
| M-02 ERC-20 vault eviction | Active-set design | 1 | S |
| M-05 unbounded loops | Active-set design | 1 | M |
| C-01 reentrant finalize | Execution model | 2 | L |
| C-02 approve bypasses ledger | Execution model | 2 | L |
| L-02 excess top-up stranded | Execution model | 2 | S |
| M-04 unsafe ERC-20 accounting | Execution model | 2 | S |
| H-01 cancel/veto strands funds | Lifecycle recovery | 3 | M |
| M-03 refund correctness | Lifecycle recovery | 3 | M |
| H-03 one GI NFT → many claims | Rewards accounting | 4 | S |
| M-01 reward overallocation | Rewards accounting | 4 | M |
| M-06 lockParts bypass | Polish | 5 | S |
| L-01 ERC-1271 malformed-sig revert | Polish | 5 | S |

Phase 0 is independent and unblocks the Sepolia rehearsal in parallel. Phases 1–5 are ordered by
blast radius and dependency (active-set hardening underpins the paged-freeze boundary the execution
model relies on; lifecycle recovery depends on per-proposal escrows existing).

---

## §A. Architecture — per-proposal fund isolation (C-01, C-02; enables L-02, M-04)

### The defect, precisely
All collected funds live commingled in the `ShwounsDAOLogic` facade. `ss.collected[asset]`
(`ShwounsDAOProposals.sol:642`) is a *ledger*, not custody. Two consequences:

- **C-01:** `finalize` (`ShwounsDAOProposals.sol:651-681`) makes external calls (`:666-676`) before
  writing `ss.finalized`/`p.executed` (`:678-679`); the facade wrapper (`ShwounsDAOLogic.sol:342`)
  has no guard. A recipient re-enters, re-passes the `Collected` gate, and pays twice — the second
  payment drawn from the shared pool, i.e. another proposal's money.
- **C-02:** a passed proposal can `token.approve(attacker, max)`; the allowance is granted over the
  *shared* balance and (being an allowance) **persists across transactions**, reaching any ERC-20
  that later transits the facade.

### Why "move funds into the facade, execute, sweep back" (v1) does NOT work
v1 proposed keeping the facade as the single executor, moving only the finalizing proposal's funds in,
executing, then sweeping back to zero — arguing a lingering approval would then find an empty wallet.
**This fails:** proposal execution is arbitrary, so an action can produce an *unlisted* asset in the
facade — e.g. `router.swap(A → B, recipient = facade)`, or a contract that pays the executor in
token B. The sweep only knows the proposal's listed assets (`ss.assets`); token B strands in the
facade. Because the facade identity is **reused** across proposals, a later proposal's
`approve(B, attacker)` drains it. You cannot prove "facade holds zero of every asset" when the
facade makes arbitrary calls. Robust isolation requires the **executing identity to be unique per
proposal**, so any stray output asset is reachable only by the proposal that produced it.

### Selected design — Option A: per-proposal escrow executes ALL actions + authenticated execution
**Decision (confirmed):** every action — value-bearing and governance — runs from the proposal's own
escrow, which holds only that proposal's assets. Unrestricted governance composability, at the cost of
a larger access-control surface, gated by a dedicated architecture review before implementation and a
focused audit after (§G). A round-3 review of this section is incorporated below.

**A1. Escrows execute everything; hold only their proposal's assets.** Each escrow is an **EIP-1167
minimal-proxy clone of one fixed, non-upgradeable `ProposalEscrow` implementation**, deployed
deterministically (CREATE2, salt = `proposalId`) **eagerly at `queue`** (settled). `collect`/`topUp`
route funds into escrow_X; `finalize` has escrow_X make every `target.call{value}(data)`. escrow_X is a
unique, single-use identity, so any stray output asset lands in escrow_X and is reachable only by
proposal X — C-01/C-02 closed by construction. **Clones (not constructor-immutable instances) so all
escrows share one identical runtime codehash** — see A3.4. The escrow never stores its own
`proposalId`; DAOLogic establishes identity from the CREATE2 address and supplies the action list.

**A2. Escrows are non-upgradeable, deterministic, DAOLogic-only — with no clone initializer (round-5
finding 1).** EIP-1167 clones take no constructor args, so the `ProposalEscrow` **implementation** is
deployed once **after DAOLogic** with `immutable daoLogic = <DAOLogic proxy address>` and `immutable
residualSink = <GR>` baked into its runtime; clones delegatecall in and read those immutables — **no
`initialize()` anywhere**. This is deliberate: an initializer on a deterministic clone address is a
front-running/takeover surface (anyone could init it first). `escrow.execute(...)` requires
`msg.sender == daoLogic` (the proxy address is upgrade-stable, so DAOLogic upgrades don't change it);
DAOLogic supplies the action list (dumb executor). DAOLogic records the escrow-impl address once during
bootstrap (locked).

**A3. Executor authentication — fully specified (round-3 finding 7).** Store **`activeProposalId`**,
not just an address. `isActiveExecutor(addr)` returns true iff ALL hold:
1. execution is in progress (`_executing == true`);
2. `activeProposalId != 0` and that proposal is in the **`Executing`** status — a distinct transient
   state, NOT terminal `Executed`;
3. `addr == escrowAddressOf(activeProposalId)` (DAOLogic recomputes the deterministic CREATE2 address);
4. `addr.codehash == EXPECTED_ESCROW_CODEHASH` (round-4 finding 3). This is well-defined **only because
   escrows are identical-runtime EIP-1167 clones (A1)** — constructor immutables would give each escrow
   a different runtime codehash and break this check. Proposal identity comes from the CREATE2 address
   (condition 3), never from per-escrow code.

**Finalize ordering — terminal `Executed` set LAST (round-6 finding 1, corrects the v5 CEI wording).**
The reentrancy "effect" set *before* the external calls is the **`_executing` lock + `activeProposalId`
(→ `Executing` status)** — NOT `p.executed`. Sequence: check `Collected`; solvency check; set
`_executing`/`activeProposalId` (status → `Executing`); `escrow.execute(...)`; on return **clear
`_executing`/`activeProposalId` and only THEN set `p.executed` (status → terminal `Executed`)**. Setting
`executed` before the calls (v5's mistaken wording) is unsafe precisely because A8's permissionless
rescue gates on the terminal state: a reentrant action could pass that gate mid-execution and sweep the
live escrow. With `executed` set last, during execution the status is `Executing`, so **both** nested
`finalize` (Collected gate + `_executing` lock) **and** nested `rescue` (terminal gate) revert. No
external call happens between the calls returning and the state writes, so there is no reentrancy window.
The same "set terminal only after all transfers complete, behind a guard" rule applies to the refund
path. Stale and cross-proposal authorization both fail (conditions 1–3).

**A4. Lock scopes to nested *execution*, not all of DAOLogic.** Governance actions require the active
escrow to call back into DAOLogic (admin setters, `upgradeTo`). A blanket `nonReentrant` over DAOLogic
would block that. The lock guards the `finalize`/execute entrypoint specifically (no nested finalize),
while governance functions stay callable *by the active escrow* via `isActiveExecutor`. **This seam is
the highest-risk part of the design** — primary focus of the dedicated review.

**A5. Authorization is a stateless library + per-contract adapters, resolved through an
auth-registry-deployed-first (round-3 finding 1 + round-4 finding 1).** Two constraints: a single
storage-bearing base would shift the `ShwounsAuctionHouse` proxy and doesn't fit DAOLogic's `ds.admin`;
**and the deployment order builds every governed contract before the DAO proxy exists** (Deploy step 6),
so an `immutable daoLogic` in their constructors is impossible. **Chosen mechanism (of the reviewer's
two options): a tiny `GovernanceAuthRegistry`**. **Deployment order (round-6 finding 3): `Bootstrap` is
deployed FIRST and itself deploys the registry**, so the registry takes its binder (`Bootstrap`) at
construction — resolving the circularity of "registry first, but only the later-deployed Bootstrap may
bind it." The registry holds the DAOLogic address set once then permanently locked, and exposes
`isActiveExecutor(addr)` (forwarding to DAOLogic's transient state). **Fail-closed binding + forwarding
(round-5 finding 4):** only `Bootstrap` (the registry's construction-time binder) may bind DAOLogic,
**exactly once**, to a **nonzero, deployed** (`code.length > 0`) proxy. While unbound,
`isActiveExecutor` returns **false** (never reverts, never authorizes). After binding, the forward to
DAOLogic is defensive (`try/catch`); a revert, malformed return, or zero/short response all resolve to
**unauthorized**. Authorization is the one thing that must never fail open. Every governed contract takes
an **`immutable governanceAuth`** reference
(the registry exists before them — ordering solved) and adds no mutable auth storage:
- **6 non-upgradeable `Ownable`** (`GovernanceRewards`, `ApprovalRegistry`, `GovernanceIncentivesNFT`,
  `ShwounsToken`, `ShwounsDescriptor`, `ShwounsVaultRegistry`): override OZ 4.9.6's `virtual
  _checkOwner()` to also accept `governanceAuth.isActiveExecutor(msg.sender)`.
- **`OwnableUpgradeable`+UUPS `ShwounsAuctionHouse`** (proxy — no new slot): same `_checkOwner()`
  override against the `immutable governanceAuth` (immutables live in impl bytecode, not proxy storage).
- **`ShwounsDAOLogic` `ds.admin`**: modify the existing `onlyAdmin` modifier to add the
  `isActiveExecutor(msg.sender)` path (it reads its own transient state directly).

*(Rejected alternative: a one-time-locked `setDAOLogic` per contract — works (matches the existing
`ShwounsVaultRegistry.setDAOLogic` pattern) but adds a mutable slot + lock to all seven, including the
proxy, and seven bind points instead of one. The registry centralizes the trust to a single audited
bind.)*

**A6. `GovernanceIncentivesNFT` rewiring (round-3 finding 2).** Today `mint()` forwards proceeds to
`owner()` (`GovernanceIncentivesNFT.sol:41`) and `setMintPrice` is `onlyOwner` (`:46`), and Deploy
makes **GR the owner** — so an escrow can never govern the NFT. **Decouple proceeds from ownership:**
add a `proceedsRecipient` (set to GR) that `mint()` forwards to; make the **owner = governance**
(adopts A5). Then `setMintPrice` is governable and proceeds still reach GR.

**A7. Residual invariant — narrower and enforceable (round-3 finding 4).** "Single-use, never refilled"
is NOT literally enforceable: anyone can send ETH/tokens to a finalized escrow's known address. The
correct invariant is **"no protocol path ever routes another proposal's assets into an old escrow."**
Cross-proposal theft stays impossible; the only residual exposure is that a lingering approval could
drain a *later voluntary/accidental* deposit to that escrow — user error, documented, out of the
isolation guarantee.

**A8. Residual recovery — specified (round-3 finding 5).** `rescueFromEscrow(proposalId, asset, kind)`
is **permissionless** (settled) but **strictly terminal-state-gated (round-5 finding 2):** it reverts
unless the proposal is in a terminal state — `finalize` succeeded (executed) **or** refund completed.
Before that, the escrow holds live proposal funding awaiting execution/refund, and permissionless rescue
would let anyone sweep it to GR (fund theft). After the gate, only stray residuals remain. It:
- handles ETH, ERC-20, ERC-721, ERC-1155 as **plain constrained transfers** — never an arbitrary
  call, and **never sets `_activeExecutor`** (so rescue can't become a second execution path that
  re-authorizes a stale escrow);
- assets locked inside external protocols are **out of scope** (the proposal author owns that risk —
  documented);
- **allocation rule (settled, round-4 finding 4):** send residuals to a **fixed
  governance-controlled sink = `GovernanceRewards`**, whose recipient address is **immutable**.
  Contribution-weighted "ETH-denominated" attribution is rejected — it needs a price oracle for ERC-20
  inputs and is manipulable. No per-input-asset attribution; one immutable sink.
- **GR-as-sink prerequisite:** GR currently is only `ERC721Holder` and can `sweepETH`/`sweepERC20` (no
  ERC-1155 receiver, no generic 721/1155 sweep). To actually receive *and later recover* arbitrary
  residuals, GR must add `ERC1155Holder` and governance-gated generic `sweepERC721`/`sweepERC1155`,
  or residuals of those types can be received-but-never-recovered. Specify this with A8.

**A9. Upgrade sequencing + honest threat boundary (round-3 finding 8 + round-4 finding 2).** A
*malicious* governance-approved implementation can overwrite any slot, so we CANNOT guarantee
`upgradeToAndCall` won't alter the execution lock — that's unguaranteeable and is **explicitly stated as
outside the security model** (approving a backdoored implementation is a governance-trust failure, like
Nouns). What the design DOES enforce, for *honest* upgrades:
- **A DAOLogic self-upgrade must be the FINAL action of its proposal** (validated at queue: if any
  action targets DAOLogic `upgradeTo`/`upgradeToAndCall`, it must be last). No further actions then run
  under a possibly-incompatible new implementation in the same frame.
- **Authentication is cleared by the OLD execution frame** after the upgrade returns: the current
  finalize call continues on already-loaded old code, whose epilogue clears `_executing`/
  `activeProposalId` on the stable (storage-compatible) slots before returning.
- **Storage-compatible upgrades required** (`_executing`, `activeProposalId`, lock slots stable across
  implementations); CI layout diff (§G). Applies to both UUPS proxies (`ShwounsDAOLogic`,
  `ShwounsAuctionHouse`); an AuctionHouse upgrade doesn't touch DAOLogic's frame but still must be
  storage-compatible.
- **Auth-binding preservation check (round-5 finding 3).** `governanceAuth` is an *implementation
  immutable*, so a storage-layout diff has a **blind spot**: a new implementation can silently point at
  a different registry without any storage change. `_authorizeUpgrade` (on `ShwounsAuctionHouse` and any
  immutable-registry contract) must therefore verify the **candidate implementation reports the canonical
  registry** (`IAuthed(newImpl).governanceAuth() == CANONICAL_REGISTRY`). And **DAOLogic upgrades must
  preserve the registry-facing `isActiveExecutor(address)` ABI** (selector + semantics), or every
  governed contract's auth check breaks. Honest-misconfiguration safeguard — a fully malicious impl can
  still fake the getter and stays out of scope per the boundary above; the point is to catch good-faith
  upgrades that the storage diff can't.

**A10. Trust model — RATIFIED: no permanent EOA authority; enforced on-chain (round-3 finding 3 +
round-4 finding 5).** A documented runbook deadline is NOT a time-limited admin — bootstrap authority
must expire **on-chain**. Mechanism + sequencing (ratified):
1. A **`Bootstrap` deployer contract** (not an EOA) holds every `owner`/`admin` role transiently while
   it wires the system. The auction stays **paused** and no user assets are accepted during this phase.
2. After wiring, art setup, and verification, a **one-shot, single-transaction `finalizeBootstrap()`**
   (settled — the authority transfer is NOT checkpointed; art upload + wiring all happen beforehand, so
   no partial-handoff state can exist) atomically (a) transfers every Ownable's ownership to governance,
   (b) sets DAOLogic's admin to DAO control **directly**, and (c) **irreversibly revokes the Bootstrap
   contract's own authority** (no re-entry). It is callable exactly once.
3. **Only after `finalizeBootstrap()`** is the auction unpaused / user assets accepted.
4. **DAOLogic two-step `pendingAdmin`/`acceptAdmin` must be adjusted:** the DAO proxy can't
   autonomously submit `acceptAdmin`, so the bootstrap path assigns DAO admin **directly** (a one-shot,
   narrowly-scoped self-acceptance invoked by `finalizeBootstrap`), not via the EOA-oriented two-step.
   The two-step remains only for any later admin change, which under "no permanent EOA" is governance
   itself.
5. **"No permanent EOA" enforced after handoff — RATIFIED: structural enforcement (round-6 finding 2).**
   Override `transferOwnership`/`renounceOwnership` on every governed contract and `setPendingAdmin` on
   DAOLogic so the only permitted destinations are **the canonical DAO (read from the registry) or
   `address(0)`**. Structural enforcement and upgradeability are compatible:
   - owners/admins remain the canonical DAO or `address(0)`;
   - UUPS governance proposals can still upgrade implementations;
   - `_authorizeUpgrade` accepts **only the authenticated active proposal escrow**;
   - upgrades preserve the proxy address, ownership, and governance authority;
   - governance cannot install a permanent EOA via `transferOwnership` or `setPendingAdmin`.

   **The ratified invariant (verbatim):** *"Honest, compatible implementations structurally prohibit
   assigning owner/admin authority to an EOA; governance changes functionality through authenticated
   proxy upgrades. Malicious governance-approved implementations are outside the security model."* The
   nuance is deliberate: governance controls code, which is ultimately stronger than ownership
   restrictions — a malicious approved implementation could remove these checks, and that case sits
   within the A9 "malicious governance-approved implementation" boundary, not within this guarantee.

This replaces the current Deploy flow, which leaves DAOLogic admin un-transferred (`Deploy.s.sol:322-324`)
and relies on an external `acceptAdmin` (§F is updated to the `finalizeBootstrap` model).

### Accounting hygiene — enforced, not documented (round-3 finding 6)
- **Reentrancy lock storage:** on OZ-upgradeable 4.9.6 (sequential storage) do NOT inherit
  `ReentrancyGuardUpgradeable` (it inserts `_status` and shifts layout). Place the `executing` flag +
  `activeProposalId` **inside `ShwounsDAOTypes.Storage`, consuming its existing `uint256[50] __gap`**
  (`ShwounsDAOInterfaces.sol:139`) — reduce the gap by the slots consumed. The struct's total footprint
  stays fixed, so nothing after `ds` moves, and governance state stays centralized in `ds`. (A plain
  append to the *facade* is also layout-safe — appending to the most-derived contract never shifts
  inherited storage — but consuming the purpose-built struct gap is cleaner.) Hand-written modifiers; CI
  `forge inspect ShwounsDAOLogic storage-layout` diff (§G).
- **Exact balance-delta accounting** at `collect` AND `topUp` (credit only `balanceAfter -
  balanceBefore`), fixing M-04; **plus a solvency recheck immediately before execution** — any
  shortfall (e.g. a negative rebase between collect and finalize) **blocks execution** rather than
  executing under-funded. `SafeERC20` throughout.
- **Fundable-asset allowlist.** Rebasing/fee tokens can't be detected by interface, so enforcement is
  an explicit DAO-curated allowlist of fundable assets (+ treat any unexpected balance change as a
  shortfall via the recheck above) — not a doc note.
- **Cap `topUp`** at `requested - collected`, into the escrow; reject/refund excess (L-02).

### Tests (adversarial set)
- Rewrite `test_audit_finalizeReentrancySpendsAnotherProposalsETH`: reentrant `finalize` reverts AND
  the victim proposal still finalizes with its full 2 ETH.
- Rewrite `test_audit_approvalActionDrainsAnotherProposalsERC20` (round-3 finding 9): after the
  malicious `approve`, the attacker's `transferFrom` against the empty escrow **reverts** (standard
  ERC-20 on insufficient balance — not a 0-value move); assert the victim escrow is unchanged and
  finalizes.
- **Forged escrow:** attacker-deployed contract calling a governed function or `escrow.execute` is
  rejected (`isActiveExecutor` fails the codehash/address checks; `escrow.execute` requires DAOLogic).
- **Stale authorization:** a finished escrow calling a governed function after finalize reverts.
- **Nested execution:** an action re-entering `finalize` reverts; an action calling a DAOLogic admin
  setter / `upgradeTo` from the active escrow succeeds.
- **Cross-proposal access:** escrow_X cannot move escrow_Y's funds nor pass `isActiveExecutor` as Y.
- **Escrow codehash uniformity:** escrows for different proposals share one `EXPECTED_ESCROW_CODEHASH`
  (clone invariant); a non-clone contract at a forced address fails condition A3.4.
- **`rescueFromEscrow`:** recovers ETH/ERC-20/721/1155 to the immutable GR sink; cannot make an
  arbitrary call; does not set `_activeExecutor`.
- **Reentrant rescue during finalize (round-6 finding 1):** an action that re-enters
  `rescueFromEscrow(thisProposal)` mid-execution **reverts** (status is `Executing`, not terminal
  `Executed`); the live escrow is untouched; terminal `Executed` is observed only after `escrow.execute`
  returns. Same for re-entrant rescue during the refund path.
- **No-permanent-EOA (round-6 finding 2, if structural enforcement chosen):** a proposal calling
  `transferOwnership(EOA)` or `setPendingAdmin(EOA)` reverts; destinations = DAO or `address(0)` only.
- **Registry binding (round-6 finding 3):** the registry's binder is `Bootstrap` (its deployer); a bind
  call from any other address reverts; binding succeeds exactly once to a deployed nonzero proxy.
- **UUPS (honest-upgrade scope):** a proposal whose final action is `upgradeTo`/`upgradeToAndCall` via
  the executor path succeeds and the old frame clears authentication afterward; a non-final DAOLogic
  self-upgrade action is rejected at queue; a direct non-executor upgrade reverts. (Malicious approved
  implementations are explicitly out of scope — not tested as defensible.)
- **GI NFT:** a proposal sets `setMintPrice` via governance; mint proceeds still reach GR.
- **Bootstrap handoff:** `finalizeBootstrap()` runs once, atomically transfers all owner/admin to
  governance, revokes its own authority, and reverts on any second call; before it runs the auction is
  paused; a governed call from the (now-revoked) Bootstrap contract afterward reverts.
- Two proposals collected concurrently finalize independently under any interleaving; non-allowlisted /
  rebasing token rejected or caught by the pre-execution solvency recheck; excess `topUp` rejected (L-02).

---

## §B. Active-set hardening (C-03, M-02, M-05)

### C-03 — nonexistent-token vaults permanently DoS queueing  *(permissionless; highest practical urgency)*
**Root cause.** `createVaultFor` accepts any tokenId (`ShwounsVaultRegistry.sol:112-121`); `markActive`
only checks the caller is the deterministic vault (`:128-133`); `markPossiblyInactive` removes only on
zero ETH (`:138-145`), so a 1-wei fake vault for an unminted token is uncleanable. `queue()` copies
the whole active set in one tx (`ShwounsDAOProposals.sol:452-456`). Attacker inflates `_activeVaults`
until every funding proposal's freeze exceeds block gas — permanent.

**Fix.** Existence-gate both entry points: `createVaultFor` and `markActive` require the bound token to
exist (`try IERC721(shwounsToken).ownerOf(tokenId)` succeeds / non-zero). Gating `createVaultFor`
prevents the fake vault from being deployed at all; gating `markActive` is defense-in-depth. Pair with
the paged, bounded freeze (M-05).

**Tests (corrected).** Note `ShwounsVault._notifyActive` swallows registry reverts via `try/catch`
(`ShwounsVault.sol:285`), so a deposit does **not** revert. Rewrite
`test_audit_nonexistentTokenVaultCanPolluteActiveSet` to assert: (a) `createVaultFor(unmintedId)`
reverts; and (b) even if a vault address is forced, a 1-wei deposit **succeeds but the tokenId never
enters the active set** (the `markActive` revert is swallowed). Do not assert the deposit reverts.

### M-02 — ERC-20-funded vault evicted; also the freeze-boundary foundation
**Root cause.** `markPossiblyInactive` infers inactivity from ETH balance only
(`ShwounsVaultRegistry.sol:140`); `ShwounsVault.withdrawERC20` calls `_notifyPossiblyInactive`
unconditionally (`ShwounsVault.sol:108-114`), so `withdrawERC20(token, to, 0)` on a zero-ETH vault
evicts a fully ERC-20-funded vault.

**Fix.** **Eliminate balance-inferred removal — make the active set append-only ("ever funded").**
`recordSnapshot` already skips zero-balance vaults (`ShwounsDAOProposals.sol:541`), so correctness
doesn't need removal; growth is bounded by C-03's existence gate + M-05 pagination. Append-only is
also the precondition that makes the paged freeze sound (below): indices never shift.

**Tests.** Rewrite `test_audit_zeroERC20WithdrawalRemovesFundedVaultFromActiveSet`: the vault stays
active after a zero-amount ERC-20 withdraw and is snapshotted by an ERC-20 proposal.

### M-05 — unbounded loops; paged freeze with a fixed boundary
**Root cause.** `queue()` copies the whole set (`ShwounsDAOProposals.sol:452-456`);
`refundStuckProposal` nests asset×vault loops (`:1086-1114`).

**Fix.** Split `queue` into `queue` (Succeeded→Queued, lock asset list, **snapshot
`freezeTarget = vaultRegistry.activeVaultsLength()`**) + `freezeVaults(pid, batchSize)` paging exactly
indices `[0, freezeTarget)` with explicit `freezeProgress`. `recordSnapshot` MUST revert until
`freezeProgress == freezeTarget`. Soundness rests on the set being **append-only** (M-02): fixed
boundary + no reordering ⇒ no skips/dups (this is the same failure class as the prior review's C1).
Paginate `refundStuckProposal` similarly with per-asset/per-vault progress.

**Tests.** 1k-vault set: queue+paged-freeze completes across N bounded calls; `recordSnapshot` reverts
mid-freeze; additions during freeze land beyond `freezeTarget` and are excluded; refund completes
across pages.

---

## §C. Lifecycle recovery (H-01, M-03)

### H-01 — cancel/veto after partial collection strands funds
**Root cause.** `cancel` is permitted in `Queued`/`Snapshotted` (block-list omits them,
`ShwounsDAOProposals.sol:388-395`); `veto` in any non-`Executed` state (`:418-424`); both set a
terminal flag, and `refundStuckProposal` accepts only `Collected` (`:1084`) — partial funds strand.

**Fix (revised — recover, don't prohibit).** Do **not** block cancel/veto after a pull; the veto is an
emergency brake and must stay available once funds are moving. Instead, route any **funded,
not-yet-finalized** proposal — including `Canceled`/`Vetoed`/partially-collected — into the
escrow-based refund path: the recovery function returns the proposal's escrow balance to snapshotted
vault owners by **actual contribution** (per §A's per-proposal escrow + M-03's per-vault tracking).
This removes the v1 self-contradiction (v1 said "block veto after pull" yet tested "veto after full
collection succeeds and is refundable").

**Tests.** Rewrite `test_audit_cancelAfterPartialCollectPermanentlyStrandsFunds`: cancel after a
partial collect leaves funds fully recoverable (assert nothing stranded). Add: vetoer veto after full
collection → refundable; vault owners made whole by actual contribution.

### M-03 — refunds reward non-contributors / can omit assets
**Root cause.** Refund distributes by snapshot share (`ShwounsDAOProposals.sol:1100`), not actual
pulled; a vault drained pre-collect still receives others' funds; the admin-supplied `assetsToRefund`
can omit an asset, after which the proposal is marked finalized (`:1116-1117`) and the omitted asset
strands; raw `IERC20.transfer` (`:1108`) ignores return values.

**Fix.** Track per-(proposal, vault, asset) actually-pulled amounts during `collect` (e.g.
`ss.pulled[shwounId][asset]`) and refund exactly those from the escrow. Iterate the recorded
`ss.assets` (not a caller list) so nothing is omitted; mark finalized only when all assets/vaults are
processed (paged per M-05). `SafeERC20` throughout.

**Tests.** A vault drained pre-collect gets no cross-subsidy; others made whole. Every collected asset
refunded; nothing stranded; an incomplete asset set is rejected or paged to completion.

---

## §D. Rewards accounting (H-03, M-01)

### H-03 — one approved GI NFT authorizes every voter
**Root cause.** Eligibility checks current NFT ownership (`ApprovalRegistry.isEligible`,
`ApprovalRegistry.sol:59-66`) — transferable by design — but claims are keyed by voter **address**
(`GovernanceRewards.sol:69`, set `:198`). One token, passed hand-to-hand, lets every For/Against voter
claim; the allowlist becomes a no-op.

**Fix (keep BOTH flags).** Add `claimedByTokenId[proposalId][giTokenId]` AND keep
`voterClaimed[proposalId][voter]`. Check/set both in `claimVotingReward`. The token flag stops one NFT
authorizing many voters; the voter flag stops one voter claiming repeatedly via multiple approved NFTs
(2× their share). Dropping either reopens a double-claim path. (Optional stronger variant: bind
eligibility to ownership at the vote/snapshot block.)

**Tests.** Rewrite `test_audit_oneApprovedGINFTCanAuthorizeMultipleVoterClaims`: after the token claims
once for a proposal, transferring it and re-claiming reverts. Add: a voter holding two approved NFTs
can claim only once for a proposal.

### M-01 — reward pools overallocated → claims insolvent
**Root cause.** `allocateProposalReward` uses raw balance, no reservation accounting
(`GovernanceRewards.sol:169-175`); `refundGas` (`:214-225`) and `sweepETH` (`:250-254`) spend the same
balance; multiple pools can exceed it.

**Fix.** Track `totalReserved` (sum of unclaimed allocations) AND a decrementing
`remainingRewardPool[proposalId]`. Allocate `min(desired, balance - totalReserved)`; decrement both on
each claim by the paid share. Cap `refundGas`/`sweepETH` at `balance - totalReserved`. **Claim deadline
= 180 days (settled); after expiry the per-proposal remainder release is permissionless** — anyone can
call it to atomically release **only** `remainingRewardPool[pid]` back to unreserved and zero it (no
owner gate; pro-rata pools are rarely fully claimed, and a permissionless release avoids locking
reserved-unclaimed ETH behind an owner who may never act).

**Tests.** Rewrite `test_audit_rewardPoolsCanBeAllocatedBeyondContractBalance`: a second allocation
cannot exceed unreserved balance. Add: `sweepETH`/`refundGas` cannot touch reserved funds; post-deadline
release frees only the unclaimed remainder; all allocated pools stay claimable until the deadline.

---

## §E. Polish (M-06, L-01)

### M-06 — `lockParts()` bypass via the Art descriptor handoff
**Root cause.** `setArtDescriptor` (`ShwounsDescriptor.sol:53-55`) and `setArtInflator` (`:57-59`) are
`onlyOwner` but lack `whenPartsNotLocked`; after `lockParts` (`:137-140`) the owner can hand Art
authority to a fresh unlocked descriptor and mutate palettes/traits.

**Fix.** Add `whenPartsNotLocked` to `setArtDescriptor` and `setArtInflator` (and any other
authority-changing Art op); optionally permanently lock the handoff once parts are locked.

**Tests.** After `lockParts`, `setArtDescriptor`/`setArtInflator` revert `"Parts are locked"`; palettes
and traits are immutable through every path.

### L-01 — malformed ERC-1271 signatures revert instead of returning invalid
**Root cause.** `ShwounsVault._isValidSignature` reads `signature[64]` and dynamic offsets without
length/bounds checks (`ShwounsVault.sol:208-232`, esp. `:216`, `:220`, `:224`); malformed input reverts.

**Fix.** Validate `signature.length >= 65` before `[64]`; in the `v == 0` branch validate the embedded
offset is in-bounds before slicing; return `false` on malformed input. Document the deliberate
divergence from upstream Tokenbound `AccountV3` (this file is a fork).

**Tests (corrected).** Empty / <65-byte / garbage signatures → `isValidSignature` returns a
**non-magic value (≠ `0x1626ba7e`) and does not revert** (do not require exactly `0xffffffff`;
`bytes4(0)` is a valid failure). Valid ECDSA and v=0 contract-sig paths still succeed.

---

## §F. Deploy tooling (H-02) — Phase 0, independent

**Root cause.** The broadcast path relies on the ephemeral script's `address(this)` as temp Art
descriptor (`Deploy.s.sol:181`) and temp DAO admin (`:263`), and `deployAndStart` makes an external
self-call `this.transferOwnershipToDAO(d)` (`:339`). Foundry rejects `address(this)` in a broadcasting
script — reproduced (deploys Seeder/SVGRenderer/Inflator, then reverts).

**Fix — a persistent `Bootstrap` coordinator (unifies H-02 with A10).** The clean resolution of both
the `address(this)` failure and the handoff is the **persistent deployment coordinator** the original
finding recommended, which is the same `Bootstrap` contract A10 requires. The ephemeral script deploys
**one persistent `Bootstrap`** and delegates wiring to it; because `Bootstrap` is a real deployed
contract (not the ephemeral script), its `address(this)` is a legitimate transient owner/admin and Art
temp-descriptor — Foundry's ephemeral-address rejection no longer applies, and the temp-descriptor and
handoff-caller identities are the same contract (no `msg.sender` divergence in either broadcast or
direct-test paths). `Bootstrap` then exposes the one-shot `finalizeBootstrap()` (A10) that atomically
hands all roles to governance, sets DAO admin directly, revokes itself, leaving the auction paused.
- Drop the ephemeral-script `address(this)` usages (`Deploy.s.sol:181`, `:263`) and the
  `this.transferOwnershipToDAO` self-call (`:339`) — that logic moves into `Bootstrap`.
- **Deployment order (round-6 finding 3):** `Bootstrap` first → `Bootstrap` deploys the
  `GovernanceAuthRegistry` (binder = Bootstrap) → token / vault layer / rewards / GI NFT / approval
  registry / auction house (all take `immutable governanceAuth` = registry) → DAOLogic → `ProposalEscrow`
  impl (`immutable daoLogic` = DAOLogic proxy) → wire + art upload → `finalizeBootstrap` (binds
  `registry.daoLogic`, then transfers all ownership to the DAO and revokes Bootstrap, in one tx).

**Tests.** Anvil/forked broadcast rehearsal running the full `Deploy → Bootstrap.wire → finalizeBootstrap`
per the runbook, asserting post-conditions (all owners/admin = governance, Bootstrap revoked, locks set,
minter set, auction paused until handoff). Direct-`_deploy` unit tests drive `Bootstrap` directly (no
`address(this)`/prank fragility). `forge script … --broadcast` completes without revert.

---

## §G. Cross-cutting & exit criteria

- **Storage-layout safety (UUPS, OZ 4.9.6, sequential).** New governance state (execution lock,
  `activeProposalId`, any refund cursor/flag) consumes the existing `Storage.__gap` inside `ds`
  (`ShwounsDAOInterfaces.sol:139`), reducing the gap by the slots used — never grow the struct without a
  gap (that WOULD shift everything after `ds`), and never reorder existing fields. Add `forge inspect
  ShwounsDAOLogic storage-layout` (and the auction-house proxy) to CI and diff before/after every change.
  **Blind spot (A9):** the diff does NOT cover *implementation immutables* (e.g. `governanceAuth`), so
  pair it with the `_authorizeUpgrade` candidate-registry check rather than relying on the diff alone.
- **Regression.** Keep all 13 audit PoCs as permanent regressions, assertions flipped to safe
  behavior. 129 baseline tests stay green throughout. Add the new tests named per finding (≥1 negative
  + ≥1 positive each).
- **Deploy rehearsal** runs in CI.
- **§A (Option A) gets a dedicated architecture review BEFORE implementation** — a hard gate. Scope:
  the finalize-scoped lock vs. governance-reentrancy seam (A4); executor authentication
  (`activeProposalId` + deterministic address + codehash + executing≠executed, A3); the stateless
  authorization library + per-contract `_checkOwner()`/`onlyAdmin` adapters (A5); GI-NFT proceeds/owner
  decoupling (A6); residual invariant + `rescueFromEscrow` rules (A7–A8); UUPS upgrade invariants incl.
  `upgradeToAndCall` (A9); and the no-permanent-EOA trust model (A10). Then a **focused security audit
  after implementation**.
- After Phases 0–4, request the focused follow-up review before any mainnet deploy. Phase 5
  (M-06/L-01) may land alongside.

## Open design decisions — all resolved (v5)
**Settled (v3–v5):** execution model = **Option A**; trust model = **no permanent EOA**, on-chain
single-tx `finalizeBootstrap` (A10); GI-NFT = **governance owns, GR proceeds recipient** (A6); auth
wiring = **`GovernanceAuthRegistry` deployed first, fail-closed** (A5); escrow = **eager at `queue`,
EIP-1167 clones, impl-immutable `daoLogic`, no initializer** (A1–A2); residual sink = **immutable GR**,
rescue **permissionless but terminal-gated** (A8); reward deadline = **180d, permissionless release**
(M-01); active set = **append-only** (M-02); reentrancy/lock + `activeProposalId` slots **appended at
end of DAO storage** (§A, §G).

**All design decisions resolved** (round-6 finding 2 ratified: structural enforcement; §A10.5).
**Next step = the dedicated §A architecture review** (highest-risk target: the A4 finalize-lock /
`Executing`-status / governance-reentrancy seam — where rounds 5–6 kept surfacing subtle issues, so it
warrants a modeled review rather than another prose round), then implementation, then the
post-implementation focused audit. All still ahead of any contract code.
