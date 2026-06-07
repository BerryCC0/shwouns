# ShwounsDAOProposals
[Git Source](https://github.com/BerryCC0/shwouns/blob/c3d3c49ecaba298c2a599310448a09b917927b54/src/governance/ShwounsDAOProposals.sol)

**Title:**
Shwouns DAO Proposals library

Forked from NounsDAOProposals.sol. The propose/vote/state/cancel lifecycle
mirrors V4. The novel parts are queue → recordSnapshot → collect → finalize,
which replace V4's timelock-based execute, with per-proposal fund isolation.

Brought to NounsDAOLogicV4 parity (minus the intentional treasury/timelock/fork
removals and client-ID attribution): signed proposals (per-signer EIP-712 digest +
ERC-1271), refundable votes, candidates, objection period, dynamic quorum, and
vote-by-signature are all implemented and hardened. Remaining upstream parity item:
proposal editing (the Updatable window).


## Constants
### ERC20_TRANSFER_SELECTOR
The 4-byte selector for ERC-20 transfer(address,uint256). Used to detect
ERC-20 funding requirements in a proposal's calldata.


```solidity
bytes4 internal constant ERC20_TRANSFER_SELECTOR = bytes4(keccak256("transfer(address,uint256)"))
```


### UPGRADE_TO_SELECTOR
UUPS upgrade selectors. A DAOLogic self-upgrade must be a proposal's FINAL action (A9).


```solidity
bytes4 internal constant UPGRADE_TO_SELECTOR = bytes4(keccak256("upgradeTo(address)"))
```


### UPGRADE_TO_AND_CALL_SELECTOR

```solidity
bytes4 internal constant UPGRADE_TO_AND_CALL_SELECTOR = bytes4(keccak256("upgradeToAndCall(address,bytes)"))
```


### FREEZE_BATCH_AT_QUEUE
M-05: max active vaults frozen within queue() itself. The remainder (for a set larger
than this) is paged via freezeVaults() across later txs, keeping per-tx work bounded.


```solidity
uint256 internal constant FREEZE_BATCH_AT_QUEUE = 256
```


### DOMAIN_TYPEHASH
EIP-712 typehashes. Pinned at compile time. DOMAIN_TYPEHASH/DOMAIN_NAME_HASH back
_domainSeparator (shared with ShwounsDAOSignatures); BALLOT_TYPEHASH backs castVoteBySig.


```solidity
bytes32 internal constant DOMAIN_TYPEHASH =
    keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)")
```


### BALLOT_TYPEHASH

```solidity
bytes32 internal constant BALLOT_TYPEHASH = keccak256("Ballot(uint256 proposalId,uint8 support)")
```


### DOMAIN_NAME_HASH

```solidity
bytes32 internal constant DOMAIN_NAME_HASH = keccak256("ShwounsDAO")
```


## Functions
### propose

Create a proposal. The caller must hold votes strictly exceeding the proposal
threshold and have no other live proposal. Opens an Updatable window, then voting.


```solidity
function propose(
    ShwounsDAOTypes.Storage storage ds,
    address[] memory targets,
    uint256[] memory values,
    string[] memory signatures,
    bytes[] memory calldatas,
    string memory description
) external returns (uint256 proposalId);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`ds`|`ShwounsDAOTypes.Storage`||
|`targets`|`address[]`|The action target addresses.|
|`values`|`uint256[]`|The ETH value for each action.|
|`signatures`|`string[]`|The function signature strings for each action (GovernorBravo form).|
|`calldatas`|`bytes[]`|The calldata (or args) for each action.|
|`description`|`string`|The proposal description.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`proposalId`|`uint256`|The id of the created proposal.|


### _validateActionsAndThreshold

Validate action-array shape (equal lengths, 1..10 actions) AND that the proposer's prior
votes STRICTLY exceed the proposal threshold (`<=` reverts — matching Nouns — so a
threshold that rounds to 0 at low supply can't let a zero-vote address propose).


```solidity
function _validateActionsAndThreshold(
    ShwounsDAOTypes.Storage storage ds,
    address[] memory targets,
    uint256[] memory values,
    string[] memory signatures,
    bytes[] memory calldatas
) internal view;
```

### _enforceOneLiveProposal

Revert if msg.sender already has a proposal in flight (Active/Pending/ObjectionPeriod/
Updatable) — at most one live proposal per proposer.


```solidity
function _enforceOneLiveProposal(ShwounsDAOTypes.Storage storage ds) internal view;
```

### _writeProposal

Internal proposal-writer exposed `public` only for cross-library linking (A3 split);
not intended for external callers.

`public` so the ShwounsDAOSignatures library can reach it cross-library (A3 split).
In-library callers (propose) still reach it as a same-library JUMP, so the hot propose
path is unaffected; only the cold proposeBySigs path pays the delegatecall hop.


```solidity
function _writeProposal(
    ShwounsDAOTypes.Storage storage ds,
    uint256 proposalId,
    address[] memory targets,
    uint256[] memory values,
    string[] memory signatures,
    bytes[] memory calldatas
) public;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`ds`|`ShwounsDAOTypes.Storage`||
|`proposalId`|`uint256`|The id to write.|
|`targets`|`address[]`|The action target addresses.|
|`values`|`uint256[]`|The ETH value for each action.|
|`signatures`|`string[]`|The function signature strings for each action.|
|`calldatas`|`bytes[]`|The calldata (or args) for each action.|


### createForSigners

Cross-library entry for ShwounsDAOSignatures.proposeBySigs: validate actions (NO
proposer-threshold check — proposeBySigs enforces threshold via combined signer
power), bump the counter, write the proposal, and emit ProposalCreated. Mirrors the
propose() tail.

`public` so proposeBySigs reaches it as a DELEGATECALL in its own frame — the 9-arg
ProposalCreated emit is too stack-heavy to inline into proposeBySigs under via_ir, but
compiles cleanly here (same shape as propose). `msg.sender` is preserved across the
delegatecall, so the emitted proposer is the original caller.


```solidity
function createForSigners(
    ShwounsDAOTypes.Storage storage ds,
    address[] memory targets,
    uint256[] memory values,
    string[] memory signatures,
    bytes[] memory calldatas,
    string memory description
) public returns (uint256 proposalId);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`ds`|`ShwounsDAOTypes.Storage`||
|`targets`|`address[]`|The action target addresses.|
|`values`|`uint256[]`|The ETH value for each action.|
|`signatures`|`string[]`|The function signature strings for each action.|
|`calldatas`|`bytes[]`|The calldata (or args) for each action.|
|`description`|`string`|The proposal description.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`proposalId`|`uint256`|The id of the created proposal.|


### castVote

Cast a vote on a proposal.


```solidity
function castVote(ShwounsDAOTypes.Storage storage ds, uint256 proposalId, uint8 support) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`ds`|`ShwounsDAOTypes.Storage`||
|`proposalId`|`uint256`|The proposal to vote on.|
|`support`|`uint8`|The vote: 0=Against, 1=For, 2=Abstain.|


### castVoteWithReason

Cast a vote on a proposal with an attached reason string.


```solidity
function castVoteWithReason(
    ShwounsDAOTypes.Storage storage ds,
    uint256 proposalId,
    uint8 support,
    string calldata reason
) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`ds`|`ShwounsDAOTypes.Storage`||
|`proposalId`|`uint256`|The proposal to vote on.|
|`support`|`uint8`|The vote: 0=Against, 1=For, 2=Abstain.|
|`reason`|`string`|A free-text reason emitted in the VoteCast event.|


### castVoteBySig

Cast a vote via an EIP-712 signature (gasless / relayed voting). The recovered
signer is the voter. Routes through the same internal path as castVote so the
objection-period and dynamic-quorum logic apply identically. ECDSA-only (Nouns
parity for ballots).


```solidity
function castVoteBySig(
    ShwounsDAOTypes.Storage storage ds,
    uint256 proposalId,
    uint8 support,
    uint8 v,
    bytes32 r,
    bytes32 s
) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`ds`|`ShwounsDAOTypes.Storage`||
|`proposalId`|`uint256`|The proposal to vote on.|
|`support`|`uint8`|The vote: 0=Against, 1=For, 2=Abstain.|
|`v`|`uint8`|The ECDSA signature `v` component.|
|`r`|`bytes32`|The ECDSA signature `r` component.|
|`s`|`bytes32`|The ECDSA signature `s` component.|


### _castVoteInternal

Shared vote path for all cast variants. Allows any support while Active; only Against
during ObjectionPeriod; reverts otherwise. Records the receipt at the proposal's
start-block voting weight (no double-voting), tallies it, and — only from the Active
phase on a For vote — may trigger the objection period.


```solidity
function _castVoteInternal(
    ShwounsDAOTypes.Storage storage ds,
    address voter,
    uint256 proposalId,
    uint8 support,
    string memory reason
) internal;
```

### _maybeStartObjectionPeriod

Start the objection period iff a For vote lands in the last-minute window AND the
proposal is currently passing (For > Against AND For >= quorum). Extends voting by
objectionPeriodDurationInBlocks, during which only Against votes are accepted. No-op if
already started, the window is disabled, or the conditions aren't met.


```solidity
function _maybeStartObjectionPeriod(ShwounsDAOTypes.Storage storage ds, uint256 proposalId) internal;
```

### state

The current lifecycle state of a proposal (see ProposalState).


```solidity
function state(ShwounsDAOTypes.Storage storage ds, uint256 proposalId)
    public
    view
    returns (ShwounsDAOTypes.ProposalState);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`ds`|`ShwounsDAOTypes.Storage`||
|`proposalId`|`uint256`|The proposal to query.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`ShwounsDAOTypes.ProposalState`|The computed proposal state.|


### _isCollectComplete

True once queued, the snapshot phase is finished, and every snapshotted vault has been
collected. Zero-snapshot proposals (empty snapshottedVaults) complete immediately (C3).


```solidity
function _isCollectComplete(ShwounsDAOTypes.Storage storage ds, uint256 proposalId) internal view returns (bool);
```

### proposals

Flat, mapping-free view of a proposal (for indexers/UIs). Includes the current
dynamic quorum, computed state, signers, and snapshot/collect progress.


```solidity
function proposals(ShwounsDAOTypes.Storage storage ds, uint256 proposalId)
    external
    view
    returns (ShwounsDAOTypes.ProposalCondensed memory c);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`ds`|`ShwounsDAOTypes.Storage`||
|`proposalId`|`uint256`|The proposal to query.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`c`|`ShwounsDAOTypes.ProposalCondensed`|The condensed proposal view.|


### cancel

Cancel a proposal. Callable by the proposer/any co-signer at will, or by anyone once
the combined proposer+signer voting power has fallen to or below the threshold.
Rejected at terminal states and while Executing. Funded proposals route to refund().


```solidity
function cancel(ShwounsDAOTypes.Storage storage ds, uint256 proposalId) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`ds`|`ShwounsDAOTypes.Storage`||
|`proposalId`|`uint256`|The proposal to cancel.|


### veto

Veto a proposal (emergency brake). Vetoer only. Rejected at Executed/Executing.
Funded proposals route to refund().


```solidity
function veto(ShwounsDAOTypes.Storage storage ds, uint256 proposalId) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`ds`|`ShwounsDAOTypes.Storage`||
|`proposalId`|`uint256`|The proposal to veto.|


### queue

Queue a Succeeded proposal: extract its requested assets, validate any self-upgrade is
last, deploy its deterministic escrow (CREATE2), and begin freezing the active vault set.


```solidity
function queue(ShwounsDAOTypes.Storage storage ds, uint256 proposalId) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`ds`|`ShwounsDAOTypes.Storage`||
|`proposalId`|`uint256`|The Succeeded proposal to queue.|


### freezeVaults

Page the queue-time vault-set freeze for a set larger than FREEZE_BATCH_AT_QUEUE.
Copies the next `batchSize` active-vault indices (within [0, snapshotTargetCount))
into the proposal's frozen list. recordSnapshot reverts until this completes.


```solidity
function freezeVaults(ShwounsDAOTypes.Storage storage ds, uint256 proposalId, uint256 batchSize) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`ds`|`ShwounsDAOTypes.Storage`||
|`proposalId`|`uint256`|The Queued proposal whose freeze to advance.|
|`batchSize`|`uint256`|The number of additional vault indices to freeze this call.|


### _freezeBatch

Copy [freezeProgress, min(freezeProgress+batchSize, snapshotTargetCount)) of the live
active set into frozenVaultIds. Append-only (M-02) makes these indices stable.


```solidity
function _freezeBatch(
    ShwounsDAOTypes.Storage storage ds,
    ShwounsDAOTypes.SnapshotState storage ss,
    uint256 batchSize
) internal;
```

### _fullCalldata

Build the calldata an action actually executes with. GovernorBravo-style actions
may carry the function as a `signature` string with argument-only `calldata`; the
executed calldata is then the 4-byte selector of that signature prepended to the
args. With an empty signature, calldata is used verbatim. Both `finalize` and
asset extraction MUST use this, or signature-form actions are mis-executed and
invisible to snapshot/collect.


```solidity
function _fullCalldata(string memory signature, bytes memory data) internal pure returns (bytes memory);
```

### _extractAssetsAndAmounts

Derive the proposal's requested assets + per-asset amounts at queue time: ETH from the
sum of values[], and ERC-20s from any `transfer(to,amount)` action (both raw-calldata and
GovernorBravo signature-string encodings). Each ERC-20 must be on the M-04 fundable
allowlist (ETH is always fundable); a non-allowlisted ERC-20 reverts the queue.


```solidity
function _extractAssetsAndAmounts(
    ShwounsDAOTypes.Storage storage ds,
    uint256 proposalId,
    address[] memory targets,
    uint256[] memory values,
    string[] memory signatures,
    bytes[] memory calldatas
) internal;
```

### _validateUpgradeActionsAreLast

A9: if any action is a DAOLogic self-upgrade (upgradeTo / upgradeToAndCall targeting
this proxy), it must be the LAST action. Recognizes both raw-calldata and signature
forms via _fullCalldata — the same encoding queue-time extraction and execute() use.


```solidity
function _validateUpgradeActionsAreLast(
    address[] memory targets,
    string[] memory signatures,
    bytes[] memory calldatas
) internal view;
```

### recordSnapshot

Page the snapshot phase: record each frozen vault's per-asset balance. Sets a vault's
snapshot from its balance at the moment its page is processed (not a queue-time freeze).


```solidity
function recordSnapshot(ShwounsDAOTypes.Storage storage ds, uint256 proposalId, uint256 batchSize) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`ds`|`ShwounsDAOTypes.Storage`||
|`proposalId`|`uint256`|The Queued proposal to snapshot.|
|`batchSize`|`uint256`|The number of frozen vaults to process this call.|


### collect

Page the collect phase: pull each snapshotted vault's pro-rata share into the
proposal's escrow. Shortfalls (owner withdrew since snapshot) are accepted and logged.


```solidity
function collect(ShwounsDAOTypes.Storage storage ds, uint256 proposalId, uint256 batchSize) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`ds`|`ShwounsDAOTypes.Storage`||
|`proposalId`|`uint256`|The Snapshotted proposal to collect for.|
|`batchSize`|`uint256`|The number of snapshotted vaults to process this call.|


### _collectFromVault

Collect one vault's contribution across every requested asset into the proposal's escrow.


```solidity
function _collectFromVault(
    ShwounsDAOTypes.Storage storage ds,
    ShwounsDAOTypes.SnapshotState storage ss,
    uint256 proposalId,
    uint256 shwounId,
    address escrow
) internal;
```

### _collectAsset

Pull one (vault, asset) pro-rata share into the escrow: share = ceil(requested ×
snapshotBalance / total), capped by the vault's current balance (a withdrawal since
snapshot logs a ShortfallRecorded) and by the proposal's still-outstanding amount (so the
ceiling rounding can't over-collect). Credits the ACTUAL balance delta the escrow received
(M-04) to both the per-asset ledger (`collected`) and the per-vault tally (`pulled`, for
refunds), never the requested pull — so a fee/rebasing token can't overstate collection.


```solidity
function _collectAsset(
    ShwounsDAOTypes.SnapshotState storage ss,
    uint256 proposalId,
    uint256 shwounId,
    address vault,
    address asset,
    address escrow
) internal;
```

### finalize

Execute a fully-Collected proposal's actions from its escrow (all-or-nothing solvency
check, single global execution lock, retryable if a target reverts). Sets terminal
Executed last. The facade allocates the voter reward pool immediately after.


```solidity
function finalize(ShwounsDAOTypes.Storage storage ds, uint256 proposalId) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`ds`|`ShwounsDAOTypes.Storage`||
|`proposalId`|`uint256`|The Collected proposal to finalize.|


### _requireSolvent

Ledger + actual-balance solvency check for every requested asset, against the escrow.


```solidity
function _requireSolvent(ShwounsDAOTypes.SnapshotState storage ss, address escrow) internal view;
```

### _executeViaEscrow

Build the proposal's action list (GovernorBravo signature-form expanded to final
calldata via _fullCalldata) and have the escrow execute it.


```solidity
function _executeViaEscrow(ShwounsDAOTypes.Proposal storage p, address escrow) internal;
```

### escrowAddressOf

The deterministic escrow address for a proposal. EIP-1167 clone of the locked
implementation, CREATE2 salt = proposalId, deployer = this DAOLogic proxy (the
library executes in the facade's context, so `address(this)` is the proxy).


```solidity
function escrowAddressOf(ShwounsDAOTypes.Storage storage ds, uint256 proposalId) internal view returns (address);
```

### _expectedEscrowCodehash

The runtime codehash every escrow clone must have. Well-defined ONLY because escrows
are identical-runtime EIP-1167 clones of one locked implementation (A3.4) — the
clone runtime embeds the impl address and nothing else. A non-clone contract forced
to a predicted address fails this check.


```solidity
function _expectedEscrowCodehash(address impl) internal pure returns (bytes32);
```

### isActiveExecutor

The canonical executor-authentication predicate (review §5). True iff ALL hold:
(1) execution is in progress; (2) there is an active proposal that (3) is in the
Executing status; (4) `candidate` is exactly that proposal's deterministic escrow
address; and (5) the candidate's code is the expected clone codehash. It never trusts
a caller-supplied proposalId, escrow storage, tx.origin, or the escrow's self-report.


```solidity
function isActiveExecutor(ShwounsDAOTypes.Storage storage ds, address candidate) public view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`ds`|`ShwounsDAOTypes.Storage`||
|`candidate`|`address`|The address to authenticate (typically a governed contract's `msg.sender`).|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|True iff `candidate` is the active proposal's escrow during its finalize frame.|


### topUp

Top up a proposal's per-asset collected ledger so an under-collected (shortfall)
proposal can reach full funding and finalize (C4 / D2). Anyone may contribute: ETH
as msg.value (asset == address(0)); ERC-20s pulled via prior approval. Restricted
to assets the proposal actually requested, so funds can't be stranded.

These library functions run in the facade's context (internal linkage), so msg.value /
msg.sender are the facade call's; the facade's topUp wrapper is payable.


```solidity
function topUp(ShwounsDAOTypes.Storage storage ds, uint256 proposalId, address asset, uint256 amount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`ds`|`ShwounsDAOTypes.Storage`||
|`proposalId`|`uint256`|The Collected proposal to top up.|
|`asset`|`address`|The asset to contribute; `address(0)` for native ETH (sent as msg.value).|
|`amount`|`uint256`|The amount to contribute (capped at the outstanding shortfall).|


### _validateActionsAndThreshold_skip

Validate a proposal's action arrays (lengths, count 1..10) WITHOUT a proposer-threshold
check. Exposed `public` only for cross-library linking (A3 split); not for external use.

Same as _validateActionsAndThreshold but without the proposer-threshold check
(proposeBySigs enforces threshold differently — via combined signer power).

`public` so ShwounsDAOSignatures can reach it cross-library (A3 split).


```solidity
function _validateActionsAndThreshold_skip(
    ShwounsDAOTypes.Storage storage,
    address[] memory targets,
    uint256[] memory values,
    string[] memory signatures,
    bytes[] memory calldatas
) public pure;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`ShwounsDAOTypes.Storage`||
|`targets`|`address[]`|The action target addresses.|
|`values`|`uint256[]`|The ETH value for each action.|
|`signatures`|`string[]`|The function signature strings for each action.|
|`calldatas`|`bytes[]`|The calldata (or args) for each action.|


### _domainSeparator

The EIP-712 domain separator for ballot/proposal signatures. Exposed `public` only for
cross-library linking (A3 split); not intended for external callers.

`public` so ShwounsDAOSignatures can reach it cross-library (A3 split). castVoteBySig
(this library) reaches it as a same-library JUMP, so the ballot path is unaffected.


```solidity
function _domainSeparator(ShwounsDAOTypes.Storage storage) public view returns (bytes32);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes32`|The EIP-712 domain separator bound to this proxy + chain id.|


### refund

Permissionless contribution refund for a funded but DEAD proposal — Canceled or
Vetoed (H-01: cancel/veto are never blocked after funds move; the funds route here).
Pages over snapshotted vaults, returning each vault's ACTUAL contribution (M-03) back
to THAT vault from the escrow (F4 — the vault's receive() never reverts). Permissionless
is safe — destinations are the vaults themselves (from the registry), never the caller.
(A Collected proposal whose finalize is stuck uses the admin refundStuckProposal
instead, so a live proposal can't be permissionlessly forced into refund.)


```solidity
function refund(ShwounsDAOTypes.Storage storage ds, uint256 proposalId, uint256 batchSize) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`ds`|`ShwounsDAOTypes.Storage`||
|`proposalId`|`uint256`|The Canceled or Vetoed (and funded) proposal to refund.|
|`batchSize`|`uint256`|The number of snapshotted vaults to refund this call.|


### refundStuckProposal

Admin/governance last-resort refund for a Collected proposal whose finalize never
succeeds. Same paged, by-actual-contribution mechanics as refund(); kept admin-gated
(facade) so a live Collected proposal can't be permissionlessly forced into refund
(which would grief its finalize).


```solidity
function refundStuckProposal(ShwounsDAOTypes.Storage storage ds, uint256 proposalId, uint256 batchSize) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`ds`|`ShwounsDAOTypes.Storage`||
|`proposalId`|`uint256`|The stuck Collected proposal to unwind.|
|`batchSize`|`uint256`|The number of snapshotted vaults to refund this call.|


### _refundPaged

Paged refund engine. Returns each snapshotted vault's ACTUAL pulled amount, for every
recorded asset (ss.assets — never a caller-supplied list, so no asset is omitted), back to
that vault. The cursor advances only after a page's transfers all succeed (a
reverted page rolls back atomically and does not advance), and `refunded` is committed
only after the FINAL page — so rescue's terminal gate opens only once every contribution
has been returned.


```solidity
function _refundPaged(ShwounsDAOTypes.Storage storage ds, uint256 proposalId, uint256 batchSize) internal;
```

### _refundVault

Refund one vault's actual contribution across every recorded asset, back to THAT VAULT
(not the current Noun owner), out of the escrow. Zeroes each pulled entry before transfer
so a re-page cannot double-refund (and a revert rolls the zeroing back atomically).

F4 (refund DoS): the contribution came FROM the vault, so it returns TO the vault. The
vault's receive() never reverts (ShwounsVault), so no recipient can brick the paged refund
or the terminal `refunded` flag (which gates rescueFromEscrow) — unlike pushing ETH to the
current Noun owner, who could be a contract that rejects ETH. The owner controls the vault
and can withdraw() the returned funds; a Noun that changed hands since the contribution no
longer mis-pays a new owner. (Benign: an ETH refund re-triggers the vault's markActive →
re-adds to the append-only active set, a no-op if present; recordSnapshot skips zero
balances. ERC-20 refunds don't hit receive(), so they don't re-add.)


```solidity
function _refundVault(
    ShwounsDAOTypes.Storage storage ds,
    ShwounsDAOTypes.SnapshotState storage ss,
    address escrow,
    uint256 proposalId,
    uint256 shwounId
) internal;
```

### rescueFromEscrow

Recover stray residual assets left in a proposal's escrow, sending them to the
immutable GovernanceRewards sink. Permissionless but STRICTLY terminal-gated: only
after the proposal has reached a terminal state (Executed — committed by a successful
finalize OR by the refund path), and never while any execution is in flight. Before
terminal the escrow holds live proposal funding awaiting execution/refund, so
permissionless rescue is barred (it would be fund theft); during execution the status
is Executing (not Executed), so a reentrant rescue of the active proposal reverts here
(round-6 finding 1). The escrow performs a typed transfer to its own immutable sink —
never an arbitrary call, never a caller-supplied recipient, never touching auth.


```solidity
function rescueFromEscrow(
    ShwounsDAOTypes.Storage storage ds,
    uint256 proposalId,
    AssetKind kind,
    address asset,
    uint256 tokenId,
    uint256 amount
) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`ds`|`ShwounsDAOTypes.Storage`||
|`proposalId`|`uint256`|The terminal proposal whose escrow to sweep.|
|`kind`|`AssetKind`|The residual asset kind (ETH / ERC20 / ERC721 / ERC1155).|
|`asset`|`address`|The token contract (ignored for ETH).|
|`tokenId`|`uint256`|The token id (ERC-721/1155 only).|
|`amount`|`uint256`|The amount (ERC-1155 only).|


### quorumVotes

Compute the quorum required for a proposal, given against-votes accumulated.
When checkpoints are configured, uses dynamic quorum: minBPS + (coefficient × againstBPS / 1e6).
When no checkpoints exist, falls back to the fixed `quorumVotesBPS` recorded at creation.


```solidity
function quorumVotes(ShwounsDAOTypes.Storage storage ds, uint256 proposalId) public view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`ds`|`ShwounsDAOTypes.Storage`||
|`proposalId`|`uint256`|The proposal whose quorum to compute.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The required quorum in absolute votes.|


### _dynamicQuorumVotes

Dynamic quorum (V4 parity): quorumBPS = min(maxQuorumVotesBPS, minQuorumVotesBPS +
coefficient × againstVotesBPS / 1e6), returned in absolute votes. More Against → higher
quorum, clamped to the configured max.


```solidity
function _dynamicQuorumVotes(
    uint256 againstVotes,
    uint256 totalSupply,
    ShwounsDAOTypes.DynamicQuorumParams memory params
) internal pure returns (uint256);
```

### getDynamicQuorumParamsAt

The dynamic-quorum params in effect at a given block (public view; Nouns parity).


```solidity
function getDynamicQuorumParamsAt(ShwounsDAOTypes.Storage storage ds, uint256 blockNumber)
    external
    view
    returns (ShwounsDAOTypes.DynamicQuorumParams memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`ds`|`ShwounsDAOTypes.Storage`||
|`blockNumber`|`uint256`|The block to resolve params at.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`ShwounsDAOTypes.DynamicQuorumParams`|The dynamic-quorum params active at `blockNumber` (zeroed if before the first checkpoint).|


### _getDynamicQuorumParamsAt

Binary-search the quorum-params checkpoints for the entry in effect at `blockNumber`;
returns zeroed params for a block before the first checkpoint (callers fall back to the
fixed quorum recorded at proposal creation).


```solidity
function _getDynamicQuorumParamsAt(ShwounsDAOTypes.Storage storage ds, uint256 blockNumber)
    internal
    view
    returns (ShwounsDAOTypes.DynamicQuorumParams memory);
```

### bps2Uint

Compute `bps` basis points of `number` (floored). Exposed `public` only for
cross-library linking (A3 split); not intended for external callers.

`public` so ShwounsDAOSignatures can reach it cross-library (A3 split).


```solidity
function bps2Uint(uint256 bps, uint256 number) public pure returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`bps`|`uint256`|The basis points (1/10000).|
|`number`|`uint256`|The base value.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The floored product `number * bps / 10000`.|


## Events
### ProposalCreated
Emitted when a proposal is created.


```solidity
event ProposalCreated(
    uint256 id,
    address proposer,
    address[] targets,
    uint256[] values,
    string[] signatures,
    bytes[] calldatas,
    uint256 startBlock,
    uint256 endBlock,
    string description
);
```

### VoteCast
Emitted on each vote cast (For/Against/Abstain) with the voter's weight and reason.


```solidity
event VoteCast(address indexed voter, uint256 proposalId, uint8 support, uint256 votes, string reason);
```

### ProposalCanceled
Emitted when a proposal is canceled.


```solidity
event ProposalCanceled(uint256 id);
```

### ProposalQueued
Emitted when a proposal is queued (escrow deployed, vault-set freeze begun).


```solidity
event ProposalQueued(uint256 id);
```

### ProposalSnapshotted
Emitted once per asset when the snapshot phase completes, with the total snapshotted.


```solidity
event ProposalSnapshotted(uint256 indexed id, address indexed asset, uint256 totalSnapshotBalance);
```

### ProposalCollected
Emitted when the collect phase completes for a proposal.


```solidity
event ProposalCollected(uint256 indexed id);
```

### ProposalExecuted
Emitted when a proposal's actions execute successfully (terminal Executed).


```solidity
event ProposalExecuted(uint256 id);
```

### ProposalVetoed
Emitted when a proposal is vetoed.


```solidity
event ProposalVetoed(uint256 id);
```

### VaultSnapshotted
Emitted per (proposal, vault, asset) when a non-zero balance is recorded at snapshot.


```solidity
event VaultSnapshotted(
    uint256 indexed proposalId, uint256 indexed shwounId, address indexed asset, uint256 balance
);
```

### AssetCollectedFromVault
Emitted per (proposal, vault, asset) when an amount is actually pulled at collect.


```solidity
event AssetCollectedFromVault(
    uint256 indexed proposalId, uint256 indexed shwounId, address indexed asset, uint256 amount
);
```

### ShortfallRecorded
Emitted when a vault's collect-time balance is below its snapshot share (a shortfall).


```solidity
event ShortfallRecorded(
    uint256 indexed proposalId, uint256 indexed shwounId, address indexed asset, uint256 missingAmount
);
```

### ProposalObjectionPeriodSet
Emitted when a last-minute For-flip starts the objection period.


```solidity
event ProposalObjectionPeriodSet(uint256 indexed proposalId, uint256 objectionPeriodEndBlock);
```

### ProposalToppedUp
Emitted when someone tops up a proposal's collected ledger to cover a shortfall.


```solidity
event ProposalToppedUp(uint256 indexed proposalId, address indexed asset, uint256 amount);
```

### StuckProposalRefunded
Emitted per (proposal, asset) when a vault's actual contribution is refunded to it.


```solidity
event StuckProposalRefunded(uint256 indexed proposalId, address indexed asset, uint256 amount);
```

### ProposalRefundProgress
Emitted after each refund page, reporting cursor progress over snapshotted vaults.


```solidity
event ProposalRefundProgress(uint256 indexed proposalId, uint256 refundProgress, uint256 total);
```

### ProposalRefunded
Emitted when the final refund page completes (terminal — enables residual rescue).


```solidity
event ProposalRefunded(uint256 indexed proposalId);
```

### EscrowResidualRescued
Emitted when stray residual assets are swept from a terminal proposal's escrow to GR.


```solidity
event EscrowResidualRescued(
    uint256 indexed proposalId, uint8 kind, address indexed asset, uint256 tokenId, uint256 amount
);
```

## Errors
### ProposerVotesBelowThreshold
Thrown when the proposer's votes do not exceed the proposal threshold.


```solidity
error ProposerVotesBelowThreshold();
```

### InvalidProposalActions
Thrown when a proposal has zero actions.


```solidity
error InvalidProposalActions();
```

### ActionsArrayLengthMismatch
Thrown when a proposal's action arrays differ in length.


```solidity
error ActionsArrayLengthMismatch();
```

### TooManyActions
Thrown when a proposal has more than 10 actions.


```solidity
error TooManyActions();
```

### ProposerAlreadyHasLiveProposal
Thrown when the proposer already has a live proposal in flight.


```solidity
error ProposerAlreadyHasLiveProposal();
```

### CannotVoteTwice
Thrown when a voter tries to vote twice on the same proposal.


```solidity
error CannotVoteTwice();
```

### InvalidSupportValue
Thrown when a vote `support` value is greater than 2.


```solidity
error InvalidSupportValue();
```

### VotingClosed
Reserved: thrown when voting has closed (legacy guard).


```solidity
error VotingClosed();
```

### VotingNotOpen
Thrown when casting a vote outside the Active/ObjectionPeriod window.


```solidity
error VotingNotOpen();
```

### ProposalDoesNotExist
Thrown when referencing a proposal id that was never created.


```solidity
error ProposalDoesNotExist();
```

### ProposalAlreadyCanceled
Reserved: thrown when a proposal was already canceled (legacy guard).


```solidity
error ProposalAlreadyCanceled();
```

### ProposerAboveThresholdAndNotVetoer
Thrown when a non-proposer/non-signer cancels a proposal still above threshold.


```solidity
error ProposerAboveThresholdAndNotVetoer();
```

### InvalidProposalState
Thrown when an action is attempted from an invalid proposal state.


```solidity
error InvalidProposalState();
```

### AlreadyQueuedOrSettled
Reserved: thrown when a proposal was already queued/settled (legacy guard).


```solidity
error AlreadyQueuedOrSettled();
```

### SnapshotPhaseNotStarted
Reserved: thrown when the snapshot phase has not started (legacy guard).


```solidity
error SnapshotPhaseNotStarted();
```

### SnapshotPhaseNotComplete
Reserved: thrown when the snapshot phase is incomplete (legacy guard).


```solidity
error SnapshotPhaseNotComplete();
```

### CollectPhaseNotComplete
Reserved: thrown when the collect phase is incomplete (legacy guard).


```solidity
error CollectPhaseNotComplete();
```

### VaultAlreadyCollected
Reserved: thrown when a vault was already collected (legacy guard).


```solidity
error VaultAlreadyCollected();
```

### VaultNotSnapshotted
Reserved: thrown when a vault was not snapshotted (legacy guard).


```solidity
error VaultNotSnapshotted();
```

### InsufficientCollected
Thrown when finalize is attempted but collected funds are below the requested amount.


```solidity
error InsufficientCollected();
```

### InvalidTopUp
Thrown when a top-up is zero, for an unrequested asset, or exceeds the shortfall.


```solidity
error InvalidTopUp();
```

### NotShwounsHolder
Reserved: thrown when caller is not a Shwouns holder (legacy guard).


```solidity
error NotShwounsHolder();
```

### OnlyProposerOrVetoer
Reserved: thrown when caller is neither proposer nor vetoer (legacy guard).


```solidity
error OnlyProposerOrVetoer();
```

### OnlyVetoer
Thrown when a vetoer-only action is called by another address.


```solidity
error OnlyVetoer();
```

### NotAuthorized
Reserved: generic unauthorized guard.


```solidity
error NotAuthorized();
```

### OnlyAgainstVotesDuringObjection
Thrown when a non-Against vote is cast during the objection period.


```solidity
error OnlyAgainstVotesDuringObjection();
```

### AlreadyExecuting
Thrown when finalize/refund/rescue runs while another finalize is in flight.


```solidity
error AlreadyExecuting();
```

### EscrowImplNotSet
Thrown when queue is attempted before the ProposalEscrow implementation is set.


```solidity
error EscrowImplNotSet();
```

### NotTerminal
Thrown when rescue is attempted on a non-terminal proposal.


```solidity
error NotTerminal();
```

### EscrowCodehashMismatch
Thrown when the escrow at the predicted address is not the expected clone codehash.


```solidity
error EscrowCodehashMismatch();
```

### UpgradeMustBeLastAction
Thrown when a DAOLogic self-upgrade action is not the proposal's final action.


```solidity
error UpgradeMustBeLastAction();
```

### AssetNotFundable
Thrown when a proposal requests a non-allowlisted ERC-20 (M-04).


```solidity
error AssetNotFundable();
```

### FreezeNotComplete
Thrown when recordSnapshot runs before the queue-time vault-set freeze completes.


```solidity
error FreezeNotComplete();
```

### FreezeAlreadyComplete
Thrown when freezeVaults is called after the freeze is already complete.


```solidity
error FreezeAlreadyComplete();
```

### SigInvalid
Thrown when a vote-by-sig recovers the zero address (malformed ECDSA signature).

Used by castVoteBySig (ecrecover returning address(0)). The proposal-signature errors
live in ShwounsDAOSignatures.


```solidity
error SigInvalid();
```

### AlreadyRefunded
Thrown when a refund is attempted on a proposal already fully refunded.


```solidity
error AlreadyRefunded();
```

## Enums
### AssetKind
Residual asset kinds for rescueFromEscrow (A8).


```solidity
enum AssetKind {
    ETH,
    ERC20,
    ERC721,
    ERC1155
}
```

