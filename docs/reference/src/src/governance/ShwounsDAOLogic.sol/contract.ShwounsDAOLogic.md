# ShwounsDAOLogic
[Git Source](https://github.com/BerryCC0/shwouns/blob/c3d3c49ecaba298c2a599310448a09b917927b54/src/governance/ShwounsDAOLogic.sol)

**Inherits:**
[ShwounsDAOStorage](/src/governance/ShwounsDAOInterfaces.sol/contract.ShwounsDAOStorage.md), [ShwounsDAOEvents](/src/governance/ShwounsDAOInterfaces.sol/interface.ShwounsDAOEvents.md), Initializable, UUPSUpgradeable


## Constants
### MIN_QUORUM_VOTES_BPS_LOWER_BOUND
Lower bound for minQuorumVotesBPS (200 = 2%).


```solidity
uint16 public constant MIN_QUORUM_VOTES_BPS_LOWER_BOUND = 200
```


### MIN_QUORUM_VOTES_BPS_UPPER_BOUND
Upper bound for minQuorumVotesBPS (2000 = 20%).


```solidity
uint16 public constant MIN_QUORUM_VOTES_BPS_UPPER_BOUND = 2_000
```


### MAX_QUORUM_VOTES_BPS_UPPER_BOUND
Upper bound for maxQuorumVotesBPS (6000 = 60%).


```solidity
uint16 public constant MAX_QUORUM_VOTES_BPS_UPPER_BOUND = 6_000
```


### MIN_PROPOSAL_THRESHOLD_BPS
Lower bound for proposalThresholdBPS.


```solidity
uint256 public constant MIN_PROPOSAL_THRESHOLD_BPS = 1
```


### MAX_PROPOSAL_THRESHOLD_BPS
Upper bound for proposalThresholdBPS (1000 = 10%).


```solidity
uint256 public constant MAX_PROPOSAL_THRESHOLD_BPS = 1_000
```


### MIN_VOTING_PERIOD_BLOCKS
Lower bound for votingPeriod (~1 day in 12s blocks).


```solidity
uint256 public constant MIN_VOTING_PERIOD_BLOCKS = 7_200
```


### MAX_VOTING_PERIOD_BLOCKS
Upper bound for votingPeriod (~2 weeks).


```solidity
uint256 public constant MAX_VOTING_PERIOD_BLOCKS = 100_800
```


### MIN_VOTING_DELAY_BLOCKS
Lower bound for votingDelay (1 block).


```solidity
uint256 public constant MIN_VOTING_DELAY_BLOCKS = 1
```


### MAX_VOTING_DELAY_BLOCKS
Upper bound for votingDelay (~2 weeks).


```solidity
uint256 public constant MAX_VOTING_DELAY_BLOCKS = 100_800
```


### MAX_UPDATABLE_PERIOD_BLOCKS
Upper bound for the Updatable (proposal-editing) period (~7 days).


```solidity
uint256 public constant MAX_UPDATABLE_PERIOD_BLOCKS = 50_400
```


### MAX_QUEUE_PERIOD_BLOCKS
Upper bound for the post-vote queue window (~7 days).


```solidity
uint256 public constant MAX_QUEUE_PERIOD_BLOCKS = 50_400
```


### MAX_OBJECTION_PERIOD_BLOCKS
Upper bound for the objection-period duration (~7 days).


```solidity
uint256 public constant MAX_OBJECTION_PERIOD_BLOCKS = 50_400
```


### MAX_LAST_MINUTE_WINDOW_BLOCKS
Upper bound for the last-minute window (~7 days).


```solidity
uint256 public constant MAX_LAST_MINUTE_WINDOW_BLOCKS = 50_400
```


## State Variables
### governanceRewards
GovernanceRewards reference (Phase 5). Settable once by admin, locked after.

GovernanceRewards reference (Phase 5). Settable once by admin, then locked.


```solidity
IGovernanceRewardsForDAO public governanceRewards
```


### governanceRewardsLocked
True once `governanceRewards` has been set, after which it can never change.


```solidity
bool public governanceRewardsLocked
```


## Functions
### proposalMaxOperations

The maximum number of actions per proposal.


```solidity
function proposalMaxOperations() public pure returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The max actions (10).|


### onlyAdmin

Admin gate. Accepts the structural admin OR the currently-authenticated active
proposal escrow (A5) — so an approved governance action, executing from its escrow,
can change DAO parameters / admin within its own finalize frame, while no other
caller (stale, forged, or cross-proposal) ever passes.


```solidity
modifier onlyAdmin() ;
```

### _validateGovParams

Bounds-check the governance params at `initialize` (and any future use): votingPeriod,
votingDelay, proposalThresholdBPS within their MIN/MAX, updatable period within MAX, and a
nonzero queue period (a zero queue window would Expire proposals the instant voting ends).


```solidity
function _validateGovParams(ShwounsDAOTypes.ShwounsDAOParams calldata p) internal pure;
```

### initialize

Initialize the DAO. Deployed via UUPS proxy. Validates all governance params and
seeds the first dynamic-quorum checkpoint so dynamic quorum is live from block 0.


```solidity
function initialize(
    address admin_,
    address vetoer_,
    IShwounsTokenLike shwouns_,
    IShwounsVaultRegistry vaultRegistry_,
    ShwounsDAOTypes.ShwounsDAOParams calldata params,
    ShwounsDAOTypes.DynamicQuorumParams calldata quorumParams
) external initializer;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`admin_`|`address`|The initial admin (the Bootstrap coordinator, later handed to the DAO itself).|
|`vetoer_`|`address`|The initial vetoer (renounceable).|
|`shwouns_`|`IShwounsTokenLike`|The Shwouns token (voting-power source).|
|`vaultRegistry_`|`IShwounsVaultRegistry`|The vault registry (active-set + per-vault deployment).|
|`params`|`ShwounsDAOTypes.ShwounsDAOParams`|Governance params (votingDelay/Period, thresholdBPS, updatable/queue periods).|
|`quorumParams`|`ShwounsDAOTypes.DynamicQuorumParams`|The seed dynamic-quorum params (min/max BPS + coefficient).|


### _authorizeUpgrade

UUPS upgrade authorization (A9). DAOLogic upgrades flow ONLY through an authenticated
active proposal escrow — never a standing admin/EOA — so the "self-upgrade is the
final action" (validated at queue) and "the old finalize frame clears authentication"
invariants always hold. A direct, non-executor upgradeTo reverts.


```solidity
function _authorizeUpgrade(address) internal view override;
```

### propose

Create a proposal (see {ShwounsDAOProposals-propose}).


```solidity
function propose(
    address[] memory targets,
    uint256[] memory values,
    string[] memory signatures,
    bytes[] memory calldatas,
    string memory description
) external returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`targets`|`address[]`|The action target addresses.|
|`values`|`uint256[]`|The ETH value for each action.|
|`signatures`|`string[]`|The function signature strings for each action.|
|`calldatas`|`bytes[]`|The calldata (or args) for each action.|
|`description`|`string`|The proposal description.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The new proposal id.|


### proposeBySigs

Create a multi-Noun co-signed proposal (see {ShwounsDAOSignatures-proposeBySigs}).


```solidity
function proposeBySigs(
    ShwounsDAOTypes.ProposerSignature[] memory proposerSignatures,
    address[] memory targets,
    uint256[] memory values,
    string[] memory signatures,
    bytes[] memory calldatas,
    string memory description
) external returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`proposerSignatures`|`ShwounsDAOTypes.ProposerSignature[]`|The co-signers' EIP-712 signatures.|
|`targets`|`address[]`|The action target addresses.|
|`values`|`uint256[]`|The ETH value for each action.|
|`signatures`|`string[]`|The function signature strings for each action.|
|`calldatas`|`bytes[]`|The calldata (or args) for each action.|
|`description`|`string`|The proposal description.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The new proposal id.|


### cancelSig

Invalidate one of your proposal signatures so proposeBySigs will reject it.


```solidity
function cancelSig(bytes calldata sig) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`sig`|`bytes`|The exact signature bytes to cancel.|


### updateProposal

Edit a proposal's actions + description in its Updatable window (proposer, no signers).


```solidity
function updateProposal(
    uint256 proposalId,
    address[] memory targets,
    uint256[] memory values,
    string[] memory signatures,
    bytes[] memory calldatas,
    string memory description,
    string memory updateMessage
) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`proposalId`|`uint256`|The proposal to edit.|
|`targets`|`address[]`|The new action target addresses.|
|`values`|`uint256[]`|The new ETH value for each action.|
|`signatures`|`string[]`|The new function signature strings for each action.|
|`calldatas`|`bytes[]`|The new calldata (or args) for each action.|
|`description`|`string`|The new proposal description.|
|`updateMessage`|`string`|A human-readable note describing the edit.|


### updateProposalTransactions

Edit only a proposal's transactions in its Updatable window.


```solidity
function updateProposalTransactions(
    uint256 proposalId,
    address[] memory targets,
    uint256[] memory values,
    string[] memory signatures,
    bytes[] memory calldatas,
    string memory updateMessage
) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`proposalId`|`uint256`|The proposal to edit.|
|`targets`|`address[]`|The new action target addresses.|
|`values`|`uint256[]`|The new ETH value for each action.|
|`signatures`|`string[]`|The new function signature strings for each action.|
|`calldatas`|`bytes[]`|The new calldata (or args) for each action.|
|`updateMessage`|`string`|A human-readable note describing the edit.|


### updateProposalDescription

Edit only a proposal's description in its Updatable window.


```solidity
function updateProposalDescription(uint256 proposalId, string calldata description, string calldata updateMessage)
    external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`proposalId`|`uint256`|The proposal to edit.|
|`description`|`string`|The new proposal description.|
|`updateMessage`|`string`|A human-readable note describing the edit.|


### updateProposalBySigs

Edit a co-signed proposal in its Updatable window (all original signers must re-sign).


```solidity
function updateProposalBySigs(
    uint256 proposalId,
    ShwounsDAOTypes.ProposerSignature[] memory proposerSignatures,
    address[] memory targets,
    uint256[] memory values,
    string[] memory signatures,
    bytes[] memory calldatas,
    string memory description,
    string memory updateMessage
) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`proposalId`|`uint256`|The proposal to edit.|
|`proposerSignatures`|`ShwounsDAOTypes.ProposerSignature[]`|Re-signatures from every original signer (same set, same order).|
|`targets`|`address[]`|The new action target addresses.|
|`values`|`uint256[]`|The new ETH value for each action.|
|`signatures`|`string[]`|The new function signature strings for each action.|
|`calldatas`|`bytes[]`|The new calldata (or args) for each action.|
|`description`|`string`|The new proposal description.|
|`updateMessage`|`string`|A human-readable note describing the edit.|


### proposalDigest

Compute the EIP-712 digest a co-signer signs (see {ShwounsDAOSignatures-proposalDigest}).


```solidity
function proposalDigest(
    address proposer,
    address[] memory targets,
    uint256[] memory values,
    string[] memory signatures,
    bytes[] memory calldatas,
    string memory description,
    uint256 expirationTimestamp
) external view returns (bytes32);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`proposer`|`address`|The address that will submit proposeBySigs.|
|`targets`|`address[]`|The action target addresses.|
|`values`|`uint256[]`|The ETH value for each action.|
|`signatures`|`string[]`|The function signature strings for each action.|
|`calldatas`|`bytes[]`|The calldata (or args) for each action.|
|`description`|`string`|The proposal description.|
|`expirationTimestamp`|`uint256`|The signer's signature expiry.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes32`|The EIP-712 typed-data digest to sign.|


### isSigCancelled

Whether a signer has cancelled a given signature hash.


```solidity
function isSigCancelled(address signer, bytes32 sigHash) external view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`signer`|`address`|The signer.|
|`sigHash`|`bytes32`|The keccak hash of the signature bytes.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|True if cancelled.|


### proposalSigners

The co-signers of a proposal (empty for a normal propose()).


```solidity
function proposalSigners(uint256 proposalId) external view returns (address[] memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`proposalId`|`uint256`|The proposal id.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address[]`|The signer addresses.|


### castVote

Cast a vote on a proposal.


```solidity
function castVote(uint256 proposalId, uint8 support) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`proposalId`|`uint256`|The proposal to vote on.|
|`support`|`uint8`|The vote: 0=Against, 1=For, 2=Abstain.|


### castVoteWithReason

Cast a vote with an attached reason string.


```solidity
function castVoteWithReason(uint256 proposalId, uint8 support, string calldata reason) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`proposalId`|`uint256`|The proposal to vote on.|
|`support`|`uint8`|The vote: 0=Against, 1=For, 2=Abstain.|
|`reason`|`string`|A free-text reason emitted in the VoteCast event.|


### castVoteBySig

Cast a vote with an EIP-712 signature (gasless / relayed). Recovered signer = voter.


```solidity
function castVoteBySig(uint256 proposalId, uint8 support, uint8 v, bytes32 r, bytes32 s) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`proposalId`|`uint256`|The proposal to vote on.|
|`support`|`uint8`|The vote: 0=Against, 1=For, 2=Abstain.|
|`v`|`uint8`|The ECDSA signature `v` component.|
|`r`|`bytes32`|The ECDSA signature `r` component.|
|`s`|`bytes32`|The ECDSA signature `s` component.|


### state

The current lifecycle state of a proposal.


```solidity
function state(uint256 proposalId) external view returns (ShwounsDAOTypes.ProposalState);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`proposalId`|`uint256`|The proposal id.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`ShwounsDAOTypes.ProposalState`|The proposal state.|


### getReceipt

A voter's receipt (hasVoted, support, votes) as a struct.


```solidity
function getReceipt(uint256 proposalId, address voter) external view returns (ShwounsDAOTypes.Receipt memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`proposalId`|`uint256`|The proposal id.|
|`voter`|`address`|The voter address.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`ShwounsDAOTypes.Receipt`|The voter's receipt.|


### getReceiptUnpacked

Receipt as unpacked tuple — used by GovernanceRewards which doesn't want the struct dependency.


```solidity
function getReceiptUnpacked(uint256 proposalId, address voter)
    external
    view
    returns (bool hasVoted, uint8 support, uint96 votes);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`proposalId`|`uint256`|The proposal id.|
|`voter`|`address`|The voter address.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`hasVoted`|`bool`|Whether the voter voted.|
|`support`|`uint8`|The vote (0=Against, 1=For, 2=Abstain).|
|`votes`|`uint96`|The recorded voting weight.|


### proposalVotes

For/Against/Abstain vote totals for a proposal. Used by GovernanceRewards.


```solidity
function proposalVotes(uint256 proposalId)
    external
    view
    returns (uint256 forVotes, uint256 againstVotes, uint256 abstainVotes);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`proposalId`|`uint256`|The proposal id.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`forVotes`|`uint256`|Total For votes.|
|`againstVotes`|`uint256`|Total Against votes.|
|`abstainVotes`|`uint256`|Total Abstain votes.|


### proposalCount

The number of proposals created so far (also the latest proposal id).


```solidity
function proposalCount() external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The proposal count.|


### shwouns

The Shwouns token (voting-power source).


```solidity
function shwouns() external view returns (IShwounsTokenLike);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`IShwounsTokenLike`|The token.|


### vaultRegistry

The vault registry (active-set + per-vault deployment).


```solidity
function vaultRegistry() external view returns (IShwounsVaultRegistry);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`IShwounsVaultRegistry`|The registry.|


### votingDelay

The voting delay, in blocks (Updatable window end → voting start).


```solidity
function votingDelay() external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The voting delay in blocks.|


### votingPeriod

The voting period, in blocks.


```solidity
function votingPeriod() external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The voting period in blocks.|


### proposalThresholdBPS

The proposal threshold, in BPS of total supply.


```solidity
function proposalThresholdBPS() external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The proposal threshold BPS.|


### quorumVotesBPS

The legacy fixed-quorum BPS (fallback for pre-first-checkpoint proposals).


```solidity
function quorumVotesBPS() external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The fixed quorum BPS.|


### admin

The current admin (the DAO itself post-handoff).


```solidity
function admin() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|The admin address.|


### vetoer

The current vetoer (zero once veto power is burned).


```solidity
function vetoer() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|The vetoer address.|


### getActions

A proposal's action arrays.


```solidity
function getActions(uint256 proposalId)
    external
    view
    returns (
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas
    );
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`proposalId`|`uint256`|The proposal id.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`targets`|`address[]`|The action target addresses.|
|`values`|`uint256[]`|The ETH value for each action.|
|`signatures`|`string[]`|The function signature strings for each action.|
|`calldatas`|`bytes[]`|The calldata (or args) for each action.|


### snapshotProgress

Snapshot-phase paging progress for a proposal.


```solidity
function snapshotProgress(uint256 proposalId) external view returns (uint256 progress, uint256 target);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`proposalId`|`uint256`|The proposal id.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`progress`|`uint256`|Vaults snapshotted so far.|
|`target`|`uint256`|Total vaults to snapshot (frozen at queue).|


### collectProgress

Collect-phase paging progress for a proposal.


```solidity
function collectProgress(uint256 proposalId) external view returns (uint256 progress, uint256 target);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`proposalId`|`uint256`|The proposal id.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`progress`|`uint256`|Vaults collected so far.|
|`target`|`uint256`|Total snapshotted vaults to collect from.|


### assetsForProposal

The assets (ETH at index 0, then ERC-20s) a proposal requests funding in.


```solidity
function assetsForProposal(uint256 proposalId) external view returns (address[] memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`proposalId`|`uint256`|The proposal id.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address[]`|The asset addresses.|


### cancel

Cancel a proposal (see {ShwounsDAOProposals-cancel}).


```solidity
function cancel(uint256 proposalId) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`proposalId`|`uint256`|The proposal to cancel.|


### veto

Veto a proposal — vetoer only (see {ShwounsDAOProposals-veto}).


```solidity
function veto(uint256 proposalId) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`proposalId`|`uint256`|The proposal to veto.|


### queue

Queue a Succeeded proposal (see {ShwounsDAOProposals-queue}).


```solidity
function queue(uint256 proposalId) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`proposalId`|`uint256`|The Succeeded proposal to queue.|


### freezeVaults

Page the queue-time vault-set freeze (M-05). Needed only for a set larger than the
batch frozen within queue(); small sets are fully frozen at queue and skip this.


```solidity
function freezeVaults(uint256 proposalId, uint256 batchSize) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`proposalId`|`uint256`|The Queued proposal whose freeze to advance.|
|`batchSize`|`uint256`|The number of additional vault indices to freeze this call.|


### recordSnapshot

Page the snapshot phase (see {ShwounsDAOProposals-recordSnapshot}).


```solidity
function recordSnapshot(uint256 proposalId, uint256 batchSize) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`proposalId`|`uint256`|The Queued proposal to snapshot.|
|`batchSize`|`uint256`|The number of frozen vaults to process this call.|


### collect

Pull pro-rata from the next `batchSize` snapshotted vaults into this proposal's
collected ledger. Paged strictly over the recorded snapshotted-vault list — no
caller-supplied vault IDs (C2).


```solidity
function collect(uint256 proposalId, uint256 batchSize) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`proposalId`|`uint256`|The Snapshotted proposal to collect for.|
|`batchSize`|`uint256`|The number of snapshotted vaults to process this call.|


### topUp

Top up an under-collected proposal so it can finalize. ETH via msg.value, ERC-20
via prior approval; restricted to assets the proposal requested (C4 / D2).


```solidity
function topUp(uint256 proposalId, address asset, uint256 amount) external payable;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`proposalId`|`uint256`|The Collected proposal to top up.|
|`asset`|`address`|The asset to contribute; `address(0)` for ETH (sent as msg.value).|
|`amount`|`uint256`|The amount to contribute (capped at the outstanding shortfall).|


### finalize

Finalize a Collected proposal (executes its actions, then allocates the reward pool).


```solidity
function finalize(uint256 proposalId) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`proposalId`|`uint256`|The Collected proposal to finalize.|


### setProposalEscrowImplementation

Set the ProposalEscrow implementation (the EIP-1167 clone source). One-shot: set at
bootstrap, then permanently locked. Every proposal's escrow is a deterministic clone
of this implementation, and both the predicted escrow address and the expected clone
codehash derive from it — so it must never change once any proposal has queued.


```solidity
function setProposalEscrowImplementation(address impl) external onlyAdmin;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`impl`|`address`|The ProposalEscrow implementation address (the clone source); locked after this call.|


### proposalEscrowImplementation

The locked ProposalEscrow implementation (clone source).


```solidity
function proposalEscrowImplementation() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|The implementation address.|


### proposalEscrowImplementationLocked

Whether the ProposalEscrow implementation has been set + permanently locked. Read by
the Bootstrap finalize prechecks (the storage field exists in `ds` but had no facade
getter).


```solidity
function proposalEscrowImplementationLocked() external view returns (bool);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|True once the implementation is set and locked.|


### escrowAddressOf

The deterministic escrow address for a proposal (clone of the locked impl, CREATE2
salt = proposalId, deployer = this proxy). Well-defined before the escrow is deployed.


```solidity
function escrowAddressOf(uint256 proposalId) external view returns (address);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`proposalId`|`uint256`|The proposal id.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|The proposal's escrow address.|


### isActiveExecutor

The canonical executor-authentication result, read by governed contracts (via the
GovernanceAuthRegistry, §A5) and by this contract's own onlyAdmin gate.


```solidity
function isActiveExecutor(address candidate) external view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`candidate`|`address`|The address to authenticate.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|True iff `candidate` is the active proposal's escrow during its finalize frame.|


### executing

The global execution lock and the proposal currently Executing (0 = none). Exposed
for off-chain observers and the storage/auth invariant tests.


```solidity
function executing() external view returns (bool);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|True while a finalize is mid-flight.|


### activeProposalId

The proposal currently executing under the lock (0 = none).


```solidity
function activeProposalId() external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The active proposal id.|


### setFundableAsset

DAO-curated allowlist of fundable ERC-20 assets (M-04). A proposal that requests a
non-allowlisted ERC-20 is rejected at queue. ETH (address(0)) is always fundable.
Governable (admin = DAO, callable from the active escrow).


```solidity
function setFundableAsset(address asset, bool fundable) external onlyAdmin;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`asset`|`address`|The ERC-20 to allow or disallow (must be nonzero; ETH is always fundable).|
|`fundable`|`bool`|True to allow the asset, false to disallow.|


### isFundableAsset

Whether an asset may fund a proposal (ETH is always fundable).


```solidity
function isFundableAsset(address asset) external view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`asset`|`address`|The asset to check.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|True if fundable.|


### castRefundableVote

Cast a vote AND get gas refunded by GovernanceRewards (capped at GR's
maxRefundPerVote). Voters who don't care about gas refunds can use the
regular castVote().


```solidity
function castRefundableVote(uint256 proposalId, uint8 support) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`proposalId`|`uint256`|The proposal to vote on.|
|`support`|`uint8`|The vote: 0=Against, 1=For, 2=Abstain.|


### castRefundableVoteWithReason

castRefundableVote with an attached reason string.


```solidity
function castRefundableVoteWithReason(uint256 proposalId, uint8 support, string calldata reason) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`proposalId`|`uint256`|The proposal to vote on.|
|`support`|`uint8`|The vote: 0=Against, 1=For, 2=Abstain.|
|`reason`|`string`|A free-text reason emitted in the VoteCast event.|


### setVotingDelay

Set the voting delay (blocks). Admin/governance only; bounds-checked.


```solidity
function setVotingDelay(uint256 newVotingDelay) external onlyAdmin;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newVotingDelay`|`uint256`|The new voting delay in blocks.|


### setVotingPeriod

Set the voting period (blocks). Admin/governance only; bounds-checked.


```solidity
function setVotingPeriod(uint256 newVotingPeriod) external onlyAdmin;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newVotingPeriod`|`uint256`|The new voting period in blocks.|


### setProposalThresholdBPS

Set the proposal threshold (BPS of total supply). Admin/governance only; bounds-checked.


```solidity
function setProposalThresholdBPS(uint256 newProposalThresholdBPS) external onlyAdmin;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newProposalThresholdBPS`|`uint256`|The new threshold in BPS.|


### setQuorumVotesBPS

Legacy fixed-quorum BPS — only a fallback for proposals created before the first
dynamic-quorum checkpoint. initialize() seeds a checkpoint, so this is inert in
normal operation; dynamic quorum is the source of truth.


```solidity
function setQuorumVotesBPS(uint256 newQuorumVotesBPS) external onlyAdmin;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newQuorumVotesBPS`|`uint256`|The new fixed quorum, in BPS of total supply.|


### setLastMinuteWindowInBlocks

Set the last-minute window (blocks) that can trigger an objection period. Admin only.


```solidity
function setLastMinuteWindowInBlocks(uint32 newLastMinuteWindowInBlocks) external onlyAdmin;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newLastMinuteWindowInBlocks`|`uint32`|The new last-minute window in blocks.|


### setProposalUpdatablePeriodInBlocks

Set the Updatable (proposal-editing) window (blocks). Admin/governance only.


```solidity
function setProposalUpdatablePeriodInBlocks(uint256 newPeriod) external onlyAdmin;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newPeriod`|`uint256`|The new updatable period in blocks (0 = no edit window).|


### setProposalQueuePeriodInBlocks

Set the post-vote queue window (blocks) before a Succeeded proposal Expires. Admin only.


```solidity
function setProposalQueuePeriodInBlocks(uint256 newPeriod) external onlyAdmin;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newPeriod`|`uint256`|The new queue period in blocks (must be nonzero).|


### proposalUpdatablePeriodInBlocks

The Updatable (proposal-editing) window, in blocks.


```solidity
function proposalUpdatablePeriodInBlocks() external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The updatable period in blocks.|


### proposalQueuePeriodInBlocks

The post-vote queue window, in blocks.


```solidity
function proposalQueuePeriodInBlocks() external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The queue period in blocks.|


### setGovernanceRewards

Set the GovernanceRewards contract. Callable once.


```solidity
function setGovernanceRewards(address _gr) external onlyAdmin;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_gr`|`address`|The GovernanceRewards address.|


### setObjectionPeriodDurationInBlocks

Set how long the objection period extends voting (blocks). Admin/governance only.


```solidity
function setObjectionPeriodDurationInBlocks(uint32 newObjectionPeriodDurationInBlocks) external onlyAdmin;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newObjectionPeriodDurationInBlocks`|`uint32`|The new objection-period duration in blocks.|


### lastMinuteWindowInBlocks

The last-minute window, in blocks.


```solidity
function lastMinuteWindowInBlocks() external view returns (uint32);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint32`|The last-minute window in blocks.|


### objectionPeriodDurationInBlocks

The objection-period duration, in blocks.


```solidity
function objectionPeriodDurationInBlocks() external view returns (uint32);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint32`|The objection-period duration in blocks.|


### setPendingAdmin

A10.5: a pending admin may only be the DAO itself (address(this)) or address(0) —
never an EOA. The bootstrap handoff uses setAdminToDAO (direct); this two-step path
remains only for governance and is structurally barred from installing an EOA admin.


```solidity
function setPendingAdmin(address newPendingAdmin) external onlyAdmin;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newPendingAdmin`|`address`|The proposed admin — must be the DAO itself (address(this)) or zero.|


### setAdminToDAO

One-shot direct admin handoff to the DAO itself (A10.4). The DAO proxy can't submit
acceptAdmin autonomously, so the bootstrap coordinator (the current admin) calls this
to set the admin to the DAO directly. Afterwards the admin is the DAO, so admin
functions are reachable only through governance (an authenticated proposal escrow) —
no permanent EOA.


```solidity
function setAdminToDAO() external onlyAdmin;
```

### acceptAdmin

Accept a pending admin transfer. Callable only by the pending admin.


```solidity
function acceptAdmin() external;
```

### setPendingVetoer

Propose a new vetoer (two-step). Callable only by the current vetoer.


```solidity
function setPendingVetoer(address newPendingVetoer) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newPendingVetoer`|`address`|The proposed new vetoer.|


### acceptVetoer

Accept a pending vetoer transfer. Callable only by the pending vetoer.


```solidity
function acceptVetoer() external;
```

### burnVetoPower

Renounce the veto authority permanently. Once called, no veto possible.


```solidity
function burnVetoPower() external;
```

### setDynamicQuorumParams

Set all three dynamic-quorum params (writes a checkpoint). Admin/governance only.


```solidity
function setDynamicQuorumParams(
    uint16 newMinQuorumVotesBPS,
    uint16 newMaxQuorumVotesBPS,
    uint32 newQuorumCoefficient
) external onlyAdmin;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newMinQuorumVotesBPS`|`uint16`|New minimum quorum, in BPS (200..2000).|
|`newMaxQuorumVotesBPS`|`uint16`|New maximum quorum, in BPS (<= 6000).|
|`newQuorumCoefficient`|`uint32`|New coefficient scaling quorum by against-vote share (1e6 fixed-point).|


### setMinQuorumVotesBPS

Update only the minimum quorum BPS. Admin/governance only.


```solidity
function setMinQuorumVotesBPS(uint16 newMinQuorumVotesBPS) external onlyAdmin;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newMinQuorumVotesBPS`|`uint16`|New minimum quorum, in BPS (200..2000).|


### setMaxQuorumVotesBPS

Update only the maximum quorum BPS. Admin/governance only.


```solidity
function setMaxQuorumVotesBPS(uint16 newMaxQuorumVotesBPS) external onlyAdmin;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newMaxQuorumVotesBPS`|`uint16`|New maximum quorum, in BPS (<= 6000).|


### setQuorumCoefficient

Update only the quorum coefficient. Admin/governance only.


```solidity
function setQuorumCoefficient(uint32 newQuorumCoefficient) external onlyAdmin;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newQuorumCoefficient`|`uint32`|New coefficient scaling quorum by against-vote share (1e6 fixed-point).|


### minQuorumVotes

Current minimum quorum in absolute votes (minQuorumVotesBPS of total supply).


```solidity
function minQuorumVotes() external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The minimum quorum in votes.|


### maxQuorumVotes

Current maximum quorum in absolute votes (maxQuorumVotesBPS of total supply).


```solidity
function maxQuorumVotes() external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The maximum quorum in votes.|


### quorumVotes

The quorum (in votes) required for a proposal, accounting for dynamic quorum and
the fixed-quorum fallback for proposals created before the first checkpoint.


```solidity
function quorumVotes(uint256 proposalId) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`proposalId`|`uint256`|The proposal id.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The required quorum in votes.|


### proposals

Flat, mapping-free view of a proposal (id, votes, lifecycle, signers, state).


```solidity
function proposals(uint256 proposalId) external view returns (ShwounsDAOTypes.ProposalCondensed memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`proposalId`|`uint256`|The proposal id.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`ShwounsDAOTypes.ProposalCondensed`|The condensed proposal view.|


### proposalThreshold

The current proposal threshold in absolute votes (proposalThresholdBPS of supply).


```solidity
function proposalThreshold() external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The proposal threshold in votes.|


### getDynamicQuorumParamsCheckpointCount

The number of dynamic-quorum checkpoints recorded.


```solidity
function getDynamicQuorumParamsCheckpointCount() external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The checkpoint count.|


### getDynamicQuorumParamsAt

The dynamic-quorum params in effect at a given block.


```solidity
function getDynamicQuorumParamsAt(uint256 blockNumber)
    external
    view
    returns (ShwounsDAOTypes.DynamicQuorumParams memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`blockNumber`|`uint256`|The block to resolve params at.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`ShwounsDAOTypes.DynamicQuorumParams`|The params active at that block.|


### getDynamicQuorumParamsCheckpoint

A dynamic-quorum checkpoint by index.


```solidity
function getDynamicQuorumParamsCheckpoint(uint256 index)
    external
    view
    returns (ShwounsDAOTypes.DynamicQuorumParamsCheckpoint memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`index`|`uint256`|The checkpoint index.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`ShwounsDAOTypes.DynamicQuorumParamsCheckpoint`|The checkpoint (fromBlock + params).|


### refundStuckProposal

Admin/governance last-resort refund for a Collected proposal whose finalize never
succeeds. Paged; returns each vault's ACTUAL contribution (M-03) back to THAT vault
(F4 — the vault's receive() never reverts, so no recipient can brick the unwind; the
Noun owner controls the vault and can withdraw()).

Only callable by admin (typically DAOLogic itself via another proposal's finalize). The
stuck-proposal must be in Collected state.


```solidity
function refundStuckProposal(uint256 proposalId, uint256 batchSize) external onlyAdmin;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`proposalId`|`uint256`|The stuck Collected proposal to unwind.|
|`batchSize`|`uint256`|The number of snapshotted vaults to refund this call.|


### refund

Permissionless contribution refund for a funded Canceled or Vetoed proposal (H-01).
Returns each snapshotted vault's actual contribution back to that vault (F4); paged.


```solidity
function refund(uint256 proposalId, uint256 batchSize) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`proposalId`|`uint256`|The Canceled or Vetoed (and funded) proposal to refund.|
|`batchSize`|`uint256`|The number of snapshotted vaults to refund this call.|


### rescueFromEscrow

Recover stray residual assets from a TERMINAL proposal's escrow to the immutable
GovernanceRewards sink (A8). Permissionless — settled — but strictly terminal-gated
in the library (only after Executed; never mid-execution). ETH ignores asset/tokenId/
amount; ERC-20 uses `asset`; ERC-721 uses `asset`+`tokenId`; ERC-1155 uses
`asset`+`tokenId`(id)+`amount`.


```solidity
function rescueFromEscrow(
    uint256 proposalId,
    ShwounsDAOProposals.AssetKind kind,
    address asset,
    uint256 tokenId,
    uint256 amount
) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`proposalId`|`uint256`|The terminal proposal whose escrow to sweep.|
|`kind`|`ShwounsDAOProposals.AssetKind`|The residual asset kind (ETH / ERC20 / ERC721 / ERC1155).|
|`asset`|`address`|The token contract (ignored for ETH).|
|`tokenId`|`uint256`|The token id (ERC-721/1155 only).|
|`amount`|`uint256`|The amount (ERC-1155 only).|


### receive


```solidity
receive() external payable;
```

## Events
### GovernanceRewardsSet
Emitted once when the GovernanceRewards reference is set and locked.


```solidity
event GovernanceRewardsSet(address indexed gr);
```

### ProposalEscrowImplementationSet
Emitted once when the ProposalEscrow implementation is set and locked.


```solidity
event ProposalEscrowImplementationSet(address indexed impl);
```

### FundableAssetSet
Emitted when an ERC-20 is added to or removed from the fundable-asset allowlist.


```solidity
event FundableAssetSet(address indexed asset, bool fundable);
```

## Errors
### OnlyAdmin
Thrown when an admin-gated function is called by neither the admin nor active escrow.


```solidity
error OnlyAdmin();
```

### InvalidAddress
Thrown when a setter or initialize is given a zero address.


```solidity
error InvalidAddress();
```

### AlreadyLocked
Thrown when a one-time setter is called after it has been locked.


```solidity
error AlreadyLocked();
```

### InvalidMinQuorumVotesBPS
Thrown when minQuorumVotesBPS is out of bounds.


```solidity
error InvalidMinQuorumVotesBPS();
```

### InvalidMaxQuorumVotesBPS
Thrown when maxQuorumVotesBPS is out of bounds.


```solidity
error InvalidMaxQuorumVotesBPS();
```

### MinQuorumBPSGreaterThanMaxQuorumBPS
Thrown when minQuorumVotesBPS exceeds maxQuorumVotesBPS.


```solidity
error MinQuorumBPSGreaterThanMaxQuorumBPS();
```

### InvalidVotingPeriod
Thrown when votingPeriod is out of bounds.


```solidity
error InvalidVotingPeriod();
```

### InvalidVotingDelay
Thrown when votingDelay is out of bounds.


```solidity
error InvalidVotingDelay();
```

### InvalidProposalThresholdBPS
Thrown when proposalThresholdBPS is out of bounds.


```solidity
error InvalidProposalThresholdBPS();
```

### InvalidPeriod
Thrown when an updatable/queue/objection/last-minute period is out of bounds.


```solidity
error InvalidPeriod();
```

### NotActiveExecutor
Thrown when a UUPS upgrade is attempted by anything other than the active executor.


```solidity
error NotActiveExecutor();
```

### EscrowImplLocked
Thrown when setting the ProposalEscrow implementation after it has been locked.


```solidity
error EscrowImplLocked();
```

### AdminMustBeDAOOrZero
Thrown when a pending-admin transfer targets an address that is neither the DAO nor zero.


```solidity
error AdminMustBeDAOOrZero();
```

