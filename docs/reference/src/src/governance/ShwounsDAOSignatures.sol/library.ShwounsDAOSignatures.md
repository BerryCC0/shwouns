# ShwounsDAOSignatures
[Git Source](https://github.com/BerryCC0/shwouns/blob/c3d3c49ecaba298c2a599310448a09b917927b54/src/governance/ShwounsDAOSignatures.sol)

**Title:**
Shwouns DAO signed-proposals + proposal-editing library

Split out of ShwounsDAOProposals to keep that library under EIP-170 (audit F1). Holds the
EIP-712 multi-Noun co-signing family (proposeBySigs / updateProposalBySigs / proposalDigest
cancelSig) and the proposer-only proposal-editing family (updateProposal*). These are all
COLD paths, so routing their shared helpers through cross-library delegatecalls to
ShwounsDAOProposals is acceptable; the HOT propose/vote/state paths stay entirely in
ShwounsDAOProposals as same-library JUMPs.

Delegatecalled by the facade on the same `ds` storage (via `using ... for Storage`). It in
turn delegatecalls a handful of now-`public` ShwounsDAOProposals helpers (state,
_writeProposal, _validateActionsAndThreshold_skip, bps2Uint, _domainSeparator) — all run in
the facade's context, so `address(this)` and storage are the proxy's throughout. The EIP-712
encoding mirrors NounsDAOProposals byte-for-byte; the digest is unchanged by the split.


## Constants
### PROPOSAL_TYPEHASH
EIP-712 typehashes for signed proposals + edits. DOMAIN_TYPEHASH/DOMAIN_NAME_HASH and
BALLOT_TYPEHASH stay in ShwounsDAOProposals (the domain separator is shared).


```solidity
bytes32 internal constant PROPOSAL_TYPEHASH = keccak256(
    "Proposal(address proposer,address[] targets,uint256[] values,string[] signatures,bytes[] calldatas,string description,uint256 expiry)"
)
```


### UPDATE_PROPOSAL_TYPEHASH

```solidity
bytes32 internal constant UPDATE_PROPOSAL_TYPEHASH = keccak256(
    "UpdateProposal(uint256 proposalId,address proposer,address[] targets,uint256[] values,string[] signatures,bytes[] calldatas,string description,uint256 expiry)"
)
```


## Functions
### proposeBySigs

Create a proposal co-signed by multiple Shwoun holders. `msg.sender` is the
proposer and contributes its own votes; the signers' combined voting power plus the
proposer's must STRICTLY exceed the proposal threshold. Each signature binds the
proposer, the proposal actions, and that signer's own expiry, and is verified via
ERC-1271 (so smart-contract wallets can co-sign). Mirrors NounsDAOProposals.


```solidity
function proposeBySigs(
    ShwounsDAOTypes.Storage storage ds,
    ShwounsDAOTypes.ProposerSignature[] memory proposerSignatures,
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
|`proposerSignatures`|`ShwounsDAOTypes.ProposerSignature[]`|The co-signers' EIP-712 signatures, each with signer + expiry.|
|`targets`|`address[]`|The action target addresses.|
|`values`|`uint256[]`|The ETH value for each action.|
|`signatures`|`string[]`|The function signature strings for each action (GovernorBravo form).|
|`calldatas`|`bytes[]`|The calldata (or args) for each action.|
|`description`|`string`|The proposal description.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`proposalId`|`uint256`|The id of the created proposal.|


### _verifySignersAndCountVotes

Verify each signer's signature, enforce one-live-proposal per signer (which also
de-duplicates signers against the just-created proposal), count the votes of signers
with voting power, then add the proposer (msg.sender) the same way. Enforces the
combined-power threshold (folded in here so proposeBySigs carries no `votes` local —
via_ir stack depth) and returns the trimmed signer set.


```solidity
function _verifySignersAndCountVotes(
    ShwounsDAOTypes.Storage storage ds,
    ShwounsDAOTypes.ProposerSignature[] memory proposerSignatures,
    address[] memory targets,
    uint256[] memory values,
    string[] memory signatures,
    bytes[] memory calldatas,
    string memory description,
    uint256 proposalId
) internal returns (address[] memory signers);
```

### _enforceOneLiveProposalFor

Per-signer one-live-proposal guard (the proposeBySigs analog of _enforceOneLiveProposal):
reverts if `proposer` already has a proposal in flight. Because the proposal is created
BEFORE signatures are verified, this also de-duplicates a repeated signer for free.


```solidity
function _enforceOneLiveProposalFor(ShwounsDAOTypes.Storage storage ds, address proposer) internal view;
```

### cancelSig

Allow a signer to invalidate a specific signature. After cancellation,
proposeBySigs will reject that sig.


```solidity
function cancelSig(ShwounsDAOTypes.Storage storage ds, bytes calldata sig) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`ds`|`ShwounsDAOTypes.Storage`||
|`sig`|`bytes`|The exact signature bytes to invalidate (keyed by its keccak hash).|


### _checkProposalUpdatable

A proposal may be edited only while Updatable, only by its proposer, and (for the
non-sig path) only if it has no co-signers (those must use updateProposalBySigs).


```solidity
function _checkProposalUpdatable(
    ShwounsDAOTypes.Storage storage ds,
    uint256 proposalId,
    ShwounsDAOTypes.Proposal storage proposal
) internal view;
```

### updateProposal

Edit a proposal's actions AND description during its Updatable window. Proposer only,
and only for proposals with no co-signers (those use updateProposalBySigs).


```solidity
function updateProposal(
    ShwounsDAOTypes.Storage storage ds,
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
|`ds`|`ShwounsDAOTypes.Storage`||
|`proposalId`|`uint256`|The proposal to edit.|
|`targets`|`address[]`|The new action target addresses.|
|`values`|`uint256[]`|The new ETH value for each action.|
|`signatures`|`string[]`|The new function signature strings for each action.|
|`calldatas`|`bytes[]`|The new calldata (or args) for each action.|
|`description`|`string`|The new proposal description.|
|`updateMessage`|`string`|A human-readable note describing the edit.|


### updateProposalTransactions

Edit only a proposal's transactions during its Updatable window. Proposer only.


```solidity
function updateProposalTransactions(
    ShwounsDAOTypes.Storage storage ds,
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
|`ds`|`ShwounsDAOTypes.Storage`||
|`proposalId`|`uint256`|The proposal to edit.|
|`targets`|`address[]`|The new action target addresses.|
|`values`|`uint256[]`|The new ETH value for each action.|
|`signatures`|`string[]`|The new function signature strings for each action.|
|`calldatas`|`bytes[]`|The new calldata (or args) for each action.|
|`updateMessage`|`string`|A human-readable note describing the edit.|


### _updateProposalTransactionsInternal


```solidity
function _updateProposalTransactionsInternal(
    ShwounsDAOTypes.Storage storage ds,
    uint256 proposalId,
    address[] memory targets,
    uint256[] memory values,
    string[] memory signatures,
    bytes[] memory calldatas
) internal;
```

### updateProposalDescription

Edit only a proposal's description during its Updatable window. Proposer only.


```solidity
function updateProposalDescription(
    ShwounsDAOTypes.Storage storage ds,
    uint256 proposalId,
    string calldata description,
    string calldata updateMessage
) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`ds`|`ShwounsDAOTypes.Storage`||
|`proposalId`|`uint256`|The proposal to edit.|
|`description`|`string`|The new proposal description.|
|`updateMessage`|`string`|A human-readable note describing the edit.|


### updateProposalBySigs

Edit a co-signed proposal during its Updatable window. The proposer submits and ALL
original signers must re-sign the update (same set, same order). Signatures bind the
proposalId via UPDATE_PROPOSAL_TYPEHASH.

`txs` bundles the four action arrays into one memory pointer (the facade builds it) so
this function stays under via_ir's stack limit. Behaviour + EIP-712 digest are identical
to passing the arrays individually.


```solidity
function updateProposalBySigs(
    ShwounsDAOTypes.Storage storage ds,
    uint256 proposalId,
    ShwounsDAOTypes.ProposerSignature[] memory proposerSignatures,
    ProposalTxs memory txs,
    string memory description,
    string memory updateMessage
) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`ds`|`ShwounsDAOTypes.Storage`||
|`proposalId`|`uint256`|The co-signed proposal to edit.|
|`proposerSignatures`|`ShwounsDAOTypes.ProposerSignature[]`|Re-signatures from every original signer (same set, same order).|
|`txs`|`ProposalTxs`|The new action arrays (targets/values/signatures/calldatas) bundled.|
|`description`|`string`|The new proposal description.|
|`updateMessage`|`string`|A human-readable note describing the edit.|


### _calcProposalEncodeData

EIP-712 proposal encoding (Nouns parity). Binds the PROPOSER plus the proposal
actions; the per-signer expiry is folded in by _sigDigest. Earlier this hard-coded
proposer = address(0) and expiry = 0, so neither was bound — a relayer could swap the
submitter or the expiry while keeping a valid signature.


```solidity
function _calcProposalEncodeData(
    address proposer,
    address[] memory targets,
    uint256[] memory values,
    string[] memory signatures,
    bytes[] memory calldatas,
    string memory description
) internal pure returns (bytes memory);
```

### _sigDigest

The typed-data digest a given signer signs: binds the proposal encoding AND that
signer's own expiry, so the expiry is cryptographically committed (not malleable).


```solidity
function _sigDigest(
    ShwounsDAOTypes.Storage storage ds,
    bytes32 typehash,
    bytes memory encodeData,
    uint256 expirationTimestamp
) internal view returns (bytes32);
```

### _verifyProposalSignature

Verify one signer's signature: not cancelled, valid (ERC-1271 via SignatureChecker so
contract wallets can co-sign), and not expired. `typehash` selects propose vs update.


```solidity
function _verifyProposalSignature(
    ShwounsDAOTypes.Storage storage ds,
    bytes32 typehash,
    bytes memory encodeData,
    ShwounsDAOTypes.ProposerSignature memory ps
) internal view;
```

### _hashStringArray


```solidity
function _hashStringArray(string[] memory arr) internal pure returns (bytes32);
```

### _hashBytesArray


```solidity
function _hashBytesArray(bytes[] memory arr) internal pure returns (bytes32);
```

### proposalDigest

Compute the EIP-712 digest a signer signs for a proposal. Off-chain UIs call this
to build the signing payload. Takes the `proposer` (the address that will submit
proposeBySigs) and the signer's `expirationTimestamp`, both bound into the digest.


```solidity
function proposalDigest(
    ShwounsDAOTypes.Storage storage ds,
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
|`ds`|`ShwounsDAOTypes.Storage`||
|`proposer`|`address`|The address that will submit proposeBySigs (bound into the digest).|
|`targets`|`address[]`|The action target addresses.|
|`values`|`uint256[]`|The ETH value for each action.|
|`signatures`|`string[]`|The function signature strings for each action.|
|`calldatas`|`bytes[]`|The calldata (or args) for each action.|
|`description`|`string`|The proposal description.|
|`expirationTimestamp`|`uint256`|The signer's signature expiry (bound into the digest).|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes32`|The EIP-712 typed-data digest to sign.|


## Events
### ProposalCreated
Emitted when a proposal is created (mirrors ShwounsDAOProposals for proposeBySigs).


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

### SignatureCancelled
Emitted when a signer cancels one of their proposal signatures.


```solidity
event SignatureCancelled(address indexed signer, bytes sig);
```

### ProposalCreatedWithSigners
Emitted after proposeBySigs, listing the proposal's co-signers.


```solidity
event ProposalCreatedWithSigners(uint256 indexed id, address[] signers);
```

### ProposalUpdated
Emitted when a proposal's actions and description are edited (Updatable window).


```solidity
event ProposalUpdated(
    uint256 indexed id,
    address indexed proposer,
    address[] targets,
    uint256[] values,
    string[] signatures,
    bytes[] calldatas,
    string description,
    string updateMessage
);
```

### ProposalTransactionsUpdated
Emitted when only a proposal's transactions are edited.


```solidity
event ProposalTransactionsUpdated(
    uint256 indexed id,
    address indexed proposer,
    address[] targets,
    uint256[] values,
    string[] signatures,
    bytes[] calldatas,
    string updateMessage
);
```

### ProposalDescriptionUpdated
Emitted when only a proposal's description is edited.


```solidity
event ProposalDescriptionUpdated(
    uint256 indexed id, address indexed proposer, string description, string updateMessage
);
```

## Errors
### SigExpired
Thrown when a proposal signature has expired.


```solidity
error SigExpired();
```

### SigCancelled
Thrown when a proposal signature was cancelled by its signer.


```solidity
error SigCancelled();
```

### SigInvalid
Thrown when a proposal signature fails ERC-1271/ECDSA verification.


```solidity
error SigInvalid();
```

### SignersBelowThreshold
Thrown when the combined signer + proposer voting power does not exceed the threshold.


```solidity
error SignersBelowThreshold();
```

### CanOnlyEditUpdatableProposals
Thrown when editing a proposal that is not in the Updatable window.


```solidity
error CanOnlyEditUpdatableProposals();
```

### OnlyProposerCanEdit
Thrown when an editor is not the proposal's proposer (or the signer set mismatches).


```solidity
error OnlyProposerCanEdit();
```

### ProposerCannotUpdateProposalWithSigners
Thrown when the non-sig edit path is used on a proposal that has co-signers.


```solidity
error ProposerCannotUpdateProposalWithSigners();
```

### SignerCountMismatch
Thrown when the re-signing set size differs from the original signer set.


```solidity
error SignerCountMismatch();
```

### ProposerAlreadyHasLiveProposal
Thrown when a signer or proposer already has a live proposal in flight.


```solidity
error ProposerAlreadyHasLiveProposal();
```

## Structs
### ProposalTxs
Bundles a proposal's action arrays into one memory pointer. updateProposalBySigs takes
this instead of four separate array params to keep its stack shallow under via_ir; the
facade builds it from the individual arrays, so the external ABI is unchanged.


```solidity
struct ProposalTxs {
    address[] targets;
    uint256[] values;
    string[] signatures;
    bytes[] calldatas;
}
```

