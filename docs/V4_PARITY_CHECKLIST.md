# Shwouns Governance — NounsDAOLogicV4 Parity Checklist

Mechanical function/event-level diff of the Shwouns governance layer
(`ShwounsDAOLogic` + `ShwounsDAOProposals`) against `NounsDAOLogicV4`.

**Target (confirmed with the DAO):** full V4 parity **minus** the intentional removals
(central treasury, timelock, fork) **and minus** client-ID attribution. Legend:
✅ present · 🟰 intentional removal/deviation · 📝 note.

## Propose / edit

| NounsDAOLogicV4 | Shwouns | Status |
|---|---|---|
| `propose(...)` | `propose(targets,values,signatures,calldatas,description)` | ✅ |
| `propose(...)` + `clientId` overload | — | 🟰 clientId dropped |
| `proposeOnTimelockV1(...)` | — | 🟰 no timelock |
| `proposeBySigs(...)` | `proposeBySigs(...)` — per-signer EIP-712 digest binds proposer + expiry; ERC-1271 via `SignatureChecker`; msg.sender is proposer & contributes votes; all signers tracked | ✅ |
| `updateProposal(...)` | `updateProposal(...)` | ✅ |
| `updateProposalTransactions(...)` | `updateProposalTransactions(...)` | ✅ |
| `updateProposalDescription(...)` | `updateProposalDescription(...)` | ✅ |
| `updateProposalBySigs(...)` | `updateProposalBySigs(...)` — `UPDATE_PROPOSAL_TYPEHASH` binds proposalId | ✅ |
| `cancelSig(sig)` | `cancelSig(sig)` | ✅ |
| `proposalThreshold()` (computed) | `proposalThreshold()` | ✅ |
| `proposalMaxOperations()` | `proposalMaxOperations()` → 10 | ✅ |

## Vote

| NounsDAOLogicV4 | Shwouns | Status |
|---|---|---|
| `castVote` / `castVoteWithReason` | same | ✅ |
| `castVoteBySig(id,support,v,r,s)` | `castVoteBySig(...)` — `BALLOT_TYPEHASH`, routed through the objection-period path | ✅ |
| `castRefundableVote` / `…WithReason` | same (gas refund via GovernanceRewards) | ✅ |
| `…` + `clientId` overloads | — | 🟰 clientId dropped |
| Objection period (last-minute For-flip) | ✅ implemented (`_maybeStartObjectionPeriod`) | ✅ |

## Lifecycle

| NounsDAOLogicV4 | Shwouns | Status |
|---|---|---|
| `queue` → timelock | `queue` → freeze vault set + extract assets | 🟰 timelock replaced by snapshot→collect→finalize |
| `execute` | `recordSnapshot` → `collect` → `finalize` (+`topUp`, `refundStuckProposal`) | 🟰 per-proposal fund isolation, all-or-nothing |
| `cancel` | `cancel` — proposer or **any signer**; below-threshold sums all signers | ✅ |
| `veto` | `veto` | ✅ |
| `state` incl. `Updatable`, `Expired`, `ObjectionPeriod` | `state` incl. all three | ✅ (see Expired note) |
| Fork: `escrowToFork`/`executeFork`/`joinFork`/`withdraw*` | — | 🟰 no fork |
| `Expired` semantics | Succeeded → Expired if not queued within `proposalQueuePeriodInBlocks` (default ~7 days) | 📝 **Shwouns policy deviation** — Nouns leaves unqueued Succeeded indefinite; Shwouns adds a bounded, configurable queue deadline |

## Admin parameters + bounds

| NounsDAOLogicV4 | Shwouns | Status |
|---|---|---|
| `MIN/MAX_PROPOSAL_THRESHOLD_BPS`, `MIN/MAX_VOTING_PERIOD`, `MIN/MAX_VOTING_DELAY` | same constants (12s-block values: period 7200–100800, delay 1–100800, threshold 1–1000 BPS) | ✅ |
| `setVotingDelay/Period/ProposalThresholdBPS` (bounded) | same, **bounds enforced** | ✅ |
| `initialize` param validation | `initialize` validates all gov params **and** the dynamic-quorum seed | ✅ |
| `setLastMinuteWindowInBlocks` / `setObjectionPeriodDurationInBlocks` (bounded ≤ 7 days) | same, bounded | ✅ |
| Updatable / queue-deadline period setters (bounded ≤ 7 days) | `setProposalUpdatablePeriodInBlocks` / `setProposalQueuePeriodInBlocks` | ✅ |
| pending-admin / vetoer two-step + `burnVetoPower` | same | ✅ |
| `setQuorumVotesBPS` | retained as legacy fixed fallback (inert once dynamic quorum is seeded) | 📝 documented legacy |

## Dynamic quorum

| NounsDAOLogicV4 | Shwouns | Status |
|---|---|---|
| seeded at deploy | seeded inside `initialize` (live from block 0; eliminates the retroactive-zero window) | ✅ |
| `setDynamicQuorumParams` (bounded) | same — bounds `[200,2000]` min / `≤6000` max / min≤max with the three errors | ✅ |
| `setMinQuorumVotesBPS` / `setMaxQuorumVotesBPS` / `setQuorumCoefficient` | same | ✅ |
| `quorumVotes(id)` / `minQuorumVotes()` / `maxQuorumVotes()` | same (`quorumVotes` falls back to fixed for any pre-checkpoint proposal) | ✅ |
| `getDynamicQuorumParamsAt(block)` + checkpoint getters | same | ✅ |

## Getters

| NounsDAOLogicV4 | Shwouns | Status |
|---|---|---|
| `proposals(id)` / `proposalsV3(id)` (ProposalCondensed structs) | `proposals(id)` → one Shwouns-native `ProposalCondensed` (no clientId/fork; adds editing/objection/snapshot-collect fields + computed `state`) | ✅ 📝 single native getter (Shwouns has no V2 ABI history to preserve) |
| `getActions` / `getReceipt` | same | ✅ |
| `adjustedTotalSupply()` | `totalSupply()` (no escrow) | 🟰 no escrow |

## Events

| NounsDAOLogicV4 | Shwouns | Status |
|---|---|---|
| `ProposalCreated` (GovernorBravo-compatible) | same | ✅ |
| `ProposalCreatedWithRequirements(...)` | `ProposalCreatedWithSigners` + requirements queryable via `proposals(id)` | 📝 **resolved** — Shwouns does not emit a clientId-bearing `…WithRequirements`; signers are emitted, and threshold/quorum/updatePeriodEnd are exposed by the `proposals(id)` getter. Indexers read those. (Adding a dedicated `…WithRequirements` event is a trivial follow-up if exact Nouns event-ABI parity is later required.) |
| `ProposalUpdated` / `ProposalTransactionsUpdated` / `ProposalDescriptionUpdated` | same | ✅ |
| `*QuorumVotesBPSSet` / `QuorumCoefficientSet` | same (emit true old→new) | ✅ |
| `VoteCast` | same | ✅ |
| `VoteCastWithClientId` | — | 🟰 clientId dropped |

## Intentional removals (recap)

Central treasury, timelock (`INounsDAOExecutor`, `proposeOnTimelockV1`, `timelock`/`timelockV1`),
fork (escrow/deployer/join/execute), client-ID attribution (`clientId` params,
`proposalDataForRewards`, `VoteCastWithClientId`), and escrow-adjusted supply. All replaced or
removed by design; see `shwouns/CLAUDE.md` and the plan
`~/.claude/plans/hey-claude-we-ve-been-velvet-canyon.md`.
