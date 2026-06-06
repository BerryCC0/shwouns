# Section A Architecture Review

**Subject:** Per-proposal escrow execution and authenticated governance  
**Reviewed plan:** `REMEDIATION_PLAN.md` v6  
**Scope:** Sections A1-A10, with emphasis on the finalize / `Executing` /
governance-reentrancy boundary  
**Status:** Approved for implementation with the mandatory constraints in this document  

## 1. Executive verdict

The v6 architecture is internally coherent and closes the cross-proposal custody and
persistent-approval failures identified as C-01 and C-02.

The architecture is approved for implementation provided the implementation treats the
requirements below as invariants, not suggestions:

1. `Executing` is a real, observable lifecycle state appended to the existing enum without
   renumbering any existing value.
2. The execution lock and `activeProposalId` live inside `ShwounsDAOTypes.Storage`, consuming
   slots from its existing `__gap`. Appending them to the facade would also be layout-safe,
   but the struct gap is the required project convention and keeps governance state centralized.
3. The active proposal cannot be canceled, vetoed, refunded, rescued, topped up, queued,
   snapshotted, collected, or finalized again while it is `Executing`.
4. Executor authorization exists only while the exact deterministic escrow is on the stack
   beneath the active `finalize` call.
5. A reverted action rolls back the complete execution attempt, including every earlier
   action, the lock, and the transient lifecycle state.
6. DAOLogic self-upgrades are final actions and the old frame clears authentication before
   marking the proposal `Executed`.

No unresolved architectural decision remains within Section A. Implementation and its tests
remain subject to the focused post-implementation audit required by the remediation plan.

## 2. Components and trust boundaries

### DAOLogic proxy

DAOLogic is the state-machine owner and the only caller permitted to invoke an escrow's
execution or constrained recovery functions. Its proxy address is stable across upgrades.

DAOLogic owns:

- proposal lifecycle state;
- the global execution lock;
- `activeProposalId`;
- the locked escrow implementation address;
- deterministic escrow address calculation;
- the canonical `isActiveExecutor(address)` result.

### ProposalEscrow implementation and clones

The implementation is deployed after the DAOLogic proxy and has immutable references to:

- the DAOLogic proxy;
- the GovernanceRewards residual sink.

Clones have no initializer and no proposal-specific storage. Proposal identity is established
only by CREATE2 address derivation from the locked implementation, DAOLogic deployer, and
proposal-ID salt.

The escrow exposes two capability classes:

- `execute(actions)`, callable only by DAOLogic;
- typed residual transfers for ETH, ERC-20, ERC-721, and ERC-1155, callable only by DAOLogic
  and always directed to the immutable residual sink.

It must not expose an arbitrary-call recovery function.

GovernanceRewards must be able to receive and later recover every supported residual type.
In addition to its existing ETH/ERC-20 handling and `ERC721Holder`, it must inherit
`ERC1155Holder` and expose governance-gated generic ERC-721 and ERC-1155 sweep functions.

### GovernanceAuthRegistry

Bootstrap deploys the registry and is its immutable binder. The registry binds once to a
nonzero deployed DAOLogic proxy and then becomes immutable.

Its forwarding behavior is fail-closed:

- unbound registry: `false`;
- DAOLogic call revert: `false`;
- malformed or short return data: `false`;
- valid boolean `false`: `false`;
- only a valid boolean `true`: `true`.

### Governed contracts

Governed contracts accept either their structural owner or the currently authenticated
proposal escrow, except upgrade authorization, which must accept only the active escrow.

For honest compatible implementations, owner/admin destinations are restricted to the
canonical DAOLogic proxy or `address(0)`.

## 3. Normative lifecycle model

`Executing` must be appended to `ProposalState`; existing numeric values must not change.

```text
Collected
   |
   | finalize(pid)
   | preconditions pass
   v
Executing
   |
   | all actions return successfully
   | authentication cleared
   v
Executed

Executing
   |
   | any action reverts
   v
Collected          (entire transaction rolls back)

Canceled/Vetoed with funds
   |
   | paged refund begins
   v
Refunding
   |
   | every recorded contribution is returned
   v
Refunded
```

`Refunding` and `Refunded` may be represented by dedicated flags rather than public enum
values, but the following facts must be machine-checkable:

- rescue is unavailable until every refund page is complete;
- finalize is unavailable once refunding begins;
- refund completion is written only after the final external transfer succeeds;
- a reverted refund page does not advance its cursor.

### State precedence

For the active proposal, `state(pid)` must return `Executing` before evaluating cancellation,
veto, or terminal flags. Calls that could set cancellation or veto during `Executing` must
revert, so contradictory combinations are unreachable.

Recommended state precedence:

```text
does not exist
Executing
Vetoed
Canceled
Executed
Refunded
queued lifecycle states
pre-queue lifecycle states
```

## 4. Finalize transition

The implementation should follow this order:

```solidity
function finalize(uint256 proposalId) external {
    require(!_executing);
    require(state(proposalId) == ProposalState.Collected);

    address escrow = escrowAddressOf(proposalId);
    require(escrow.codehash == EXPECTED_ESCROW_CODEHASH);
    _requireSolvent(proposalId, escrow);

    _executing = true;
    activeProposalId = proposalId;

    ProposalEscrow(payable(escrow)).execute(encodedActionsFor(proposalId));

    activeProposalId = 0;
    _executing = false;
    _proposals[proposalId].executed = true;
    _snapshotState[proposalId].finalized = true;

    emit ProposalExecuted(proposalId);
    _allocateRewardBestEffort(proposalId);
}
```

The exact code may differ, but the ordering may not.

Important consequences:

- the lock is set before the first external call;
- terminal flags are absent during every action;
- clearing authentication performs no external call;
- terminal writes perform no external call;
- reward allocation occurs only after terminal state is committed;
- any action revert rolls the transaction back to `Collected`.

The solvency check must use actual escrow balances immediately before the lock is set.

Every executed action must use the same GovernorBravo-compatible `_fullCalldata(signature,
calldata)` encoding that queue-time asset extraction and upgrade-selector validation analyzed.
Asset extraction, upgrade validation, and execution must operate on identical final calldata
bytes; no stage may reinterpret signature-form actions differently.

## 5. Executor-authentication predicate

`isActiveExecutor(candidate)` is true if and only if:

```text
_executing == true
activeProposalId != 0
state(activeProposalId) == Executing
candidate == escrowAddressOf(activeProposalId)
candidate.codehash == EXPECTED_ESCROW_CODEHASH
```

The predicate must not rely on caller-supplied proposal IDs, escrow storage, `tx.origin`, or
the escrow reporting its own identity.

The expected clone codehash and predicted address must derive from the same locked
implementation address. Bootstrap must not be able to replace that implementation after
handoff.

## 6. Callability matrix during execution

The following matrix is normative for calls made while proposal X is `Executing`.

| Entry point | Proposal X | Other proposal | Reason |
|---|---:|---:|---|
| `finalize` | Reject | Reject | Global execution lock |
| `rescueFromEscrow` | Reject | Allowed only if independently terminal | Never expose live X funds |
| refund start/page | Reject | Allowed when independently refundable | X is already executing |
| `cancel` | Reject | Existing authorization rules | Prevent contradictory terminal flags |
| `veto` | Reject | Existing veto rules | Prevent contradictory terminal flags |
| `queue` / snapshot / collect / top-up | Reject | Existing state rules | X has left those phases |
| DAO configuration setter | Allowed only from active escrow | N/A | Approved governance action |
| governed-contract `onlyOwner` action | Allowed only from active escrow | N/A | Approved governance action |
| UUPS upgrade | Allowed only from active escrow | N/A | Must satisfy Section 9 |

For simplicity and reviewability, it is acceptable to reject rescue and refund globally while
`_executing` is true, even when they concern another proposal.

## 7. Reentrancy analysis

### Nested finalize

An action may call `finalize(X)` or `finalize(Y)`. Both must revert on the global lock. This
prevents nested authenticated execution and prevents replacing `activeProposalId`.

### Reentrant rescue

An action may call `rescueFromEscrow(X)`. It must revert because X is `Executing`, not
terminal. A rescue of Y is safe only if Y independently satisfies its terminal gate and the
implementation permits concurrent recovery.

### Cancel or veto during execution

An arbitrary callback may satisfy the normal cancellation threshold, and a vetoer may itself
be a contract. Therefore state ordering alone is insufficient: `cancel(X)` and `veto(X)` must
explicitly reject `Executing`.

### Reentrant governance calls

Only the escrow address passes active-executor authentication. If the escrow calls target T
and T calls a governed contract, that second call has `msg.sender == T` and fails unless T has
independent structural authority. Authentication does not flow transitively through targets.

### Action failure

`ProposalEscrow.execute` must bubble revert data. DAOLogic must not catch action failure.
Atomic EVM rollback restores:

- escrow balances and allowances changed by earlier actions;
- governed-contract mutations from earlier actions;
- `_executing`;
- `activeProposalId`;
- proposal lifecycle state.

This preserves retryability.

## 8. Recovery invariants

`rescueFromEscrow` is permissionless only after:

- successful finalize has committed `Executed`; or
- the paged refund process has committed refund completion.

The DAOLogic recovery entry point must recompute the escrow address and verify its codehash.
The escrow performs a typed transfer directly to immutable GovernanceRewards.

Collection is capped at each proposal's recorded requested amount, and successful execution
spends the approved requested values/transfers. Therefore ordinary vault contributions should
not remain after a successful finalize. Post-execution balances are treated as residual outputs,
including swap change, airdrops, unsolicited deposits, and funds returned to the escrow by an
action. Those residuals go to GovernanceRewards, not back to contributing vaults. Contributions
from a proposal that does not execute go through the contribution-based refund path instead.

Recovery must never:

- set `_executing` or `activeProposalId`;
- invoke the general action executor;
- choose a caller-supplied recipient;
- mark a proposal executed;
- advance refund accounting.

## 9. Upgrade invariants

DAOLogic and AuctionHouse remain UUPS-upgradeable. ProposalEscrow and the auth registry are
non-upgradeable trust anchors.

For DAOLogic:

- `_authorizeUpgrade` accepts only the authenticated active escrow;
- `upgradeTo` or `upgradeToAndCall` targeting DAOLogic must be the final proposal action;
- queue-time validation recognizes both selectors in raw-calldata and signature forms;
- the new implementation preserves storage layout, execution fields, and
  `isActiveExecutor(address)` behavior;
- the old finalize frame clears authentication after the upgrade returns.

For AuctionHouse:

- `_authorizeUpgrade` accepts only the authenticated active escrow;
- the candidate implementation must report the canonical auth registry;
- storage-layout compatibility remains mandatory.

Candidate getters are good-faith compatibility checks, not defenses against a malicious
governance-approved implementation.

## 10. Storage-layout requirements

The execution fields belong in `ShwounsDAOTypes.Storage` immediately before its `__gap`:

```solidity
bool executing;
uint256 activeProposalId;
```

Packing may change the number of consumed slots, but the storage-layout report is authoritative.
Reduce `Storage.__gap` by exactly the consumed slot count.

Using the existing struct gap is preferred because it keeps governance state centralized and
reserves the already-planned storage region without moving later fields. Appending variables to
the most-derived facade would normally place them after inherited/base storage and would not
shift preceding OpenZeppelin slots; it is not itself a corruption vector. The actual unsafe
operation is growing or reordering `Storage` without consuming its gap, which would move every
slot that follows `ds`, including inherited OpenZeppelin storage.

Any per-proposal refund cursor or lifecycle flag must likewise be appended to the appropriate
existing struct or consume a documented storage gap without reordering existing fields.

## 11. Structural authority requirements

After bootstrap:

- contract ownership is DAOLogic or zero;
- DAOLogic admin is DAOLogic;
- no pending owner/admin may be an EOA;
- `transferOwnership`, `renounceOwnership`, and admin-transfer paths enforce those destinations;
- bootstrap has no callable privileged path;
- upgrades remain available only through an authenticated proposal escrow.

Bootstrap must bind the auth registry before transferring ownership, so governed contracts can
validate the canonical DAO destination during the atomic handoff.

## 12. Mandatory implementation tests

The implementation gate requires, at minimum:

1. successful value and governance action execution from the deterministic escrow;
2. action failure rolls back earlier successful actions and returns the proposal to `Collected`;
3. nested finalize of the same and a different proposal both revert;
4. reentrant rescue, cancel, veto, refund, and top-up against the active proposal revert;
5. direct, forged, stale, and cross-proposal executor calls fail;
6. a target cannot relay active-executor authority;
7. terminal state is not observable until execution returns;
8. rescue succeeds only after execution or full refund completion;
9. refund-page failure does not advance progress;
10. DAOLogic self-upgrade succeeds only as the final action and clears authentication;
11. AuctionHouse upgrade rejects an implementation with a different auth registry;
12. ownership/admin transfer to an EOA reverts while DAO/zero destinations behave as designed;
13. storage-layout diff proves existing fields and inherited proxy storage are unchanged;
14. fuzzed action sequences never produce `_executing == false` with a nonzero
    `activeProposalId`, or `_executing == true` with an invalid active escrow.
15. signature-form actions produce identical `_fullCalldata` bytes during extraction,
    upgrade validation, and execution;
16. capped inputs are fully spent or refunded as designed, while assets returned during
    successful execution are recoverable only as GR-bound residuals;
17. GovernanceRewards safely receives and governance can sweep arbitrary ERC-721 and ERC-1155
    residuals.

## 13. Review conclusion

Under the stated governance-trust boundary, the design provides:

- per-proposal custody isolation;
- no cross-proposal use of lingering allowances;
- single active authenticated execution;
- retryable atomic proposal execution;
- terminal-gated residual recovery;
- upgradeable governed proxies without a standing EOA authority.

The architecture is approved for implementation. Approval does not cover implementation
correctness, storage-layout output, deployment behavior, or unmodeled malicious upgrade code;
those remain explicit verification items for the implementation phase and focused audit.
