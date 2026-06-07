# ShwounsDAOData
[Git Source](https://github.com/BerryCC0/shwouns/blob/c3d3c49ecaba298c2a599310448a09b917927b54/src/governance/data/ShwounsDAOData.sol)

**Title:**
ShwounsDAOData — pre-proposal candidates + on-chain feedback

Forked-down version of NounsDAOData. Stripped to event-only mode:
- Candidate bodies (targets/values/sigs/calldatas/description) live in event logs,
not contract storage. Off-chain indexers reconstruct candidates from event history.
- On-chain state is just a uniqueness map: (proposer, slug-hash) → exists, used to
reject duplicate slugs and to gate updateProposalCandidate / cancelProposalCandidate
to the original creator.
Why event-only:
- V4's NounsDAOData stores full proposal data in storage for canonical on-chain reads.
That adds ~600 LOC, dominates the audit surface, and adds significant deployment cost.
- We need pre-proposal coordination but don't need on-chain canonical data — indexers
(Ponder) can rebuild candidates from events with full fidelity.
- Signatures collected off-chain anyway (passed to proposeBySigs at promotion time).


## State Variables
### candidateActive
(creator, slugHash) → true once they've created a candidate with that slug
and not cancelled it. Used for duplicate-slug protection and update auth.


```solidity
mapping(address => mapping(bytes32 => bool)) public candidateActive
```


## Functions
### createProposalCandidate

Create a pre-proposal candidate. Anyone can create; the candidate body is
emitted in the event log for off-chain indexing.

Args bundled into a struct to avoid stack-too-deep.


```solidity
function createProposalCandidate(Candidate calldata c, string calldata slug, string calldata reason) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`c`|`Candidate`|The candidate body (targets/values/signatures/calldatas/description).|
|`slug`|`string`|A human-readable identifier scoped to msg.sender. The (sender, slug) pair must be unique among active candidates from that sender.|
|`reason`|`string`|Optional message accompanying the creation.|


### updateProposalCandidate

Update an existing candidate. Only callable by the original creator.

Args bundled into a struct to avoid stack pressure.


```solidity
function updateProposalCandidate(string calldata slug, CandidateUpdate calldata u) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`slug`|`string`|The slug identifying the candidate to update.|
|`u`|`CandidateUpdate`|The new candidate body plus an update message.|


### cancelProposalCandidate

Cancel a candidate. Only callable by the original creator. Frees the slug
for re-use.


```solidity
function cancelProposalCandidate(string calldata slug) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`slug`|`string`|The slug identifying the candidate to cancel.|


### sendCandidateFeedback

Send on-chain feedback for a candidate. Anyone can call.


```solidity
function sendCandidateFeedback(
    address candidateProposer,
    string calldata slug,
    uint8 support,
    string calldata reason
) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`candidateProposer`|`address`|The creator of the candidate being commented on.|
|`slug`|`string`|The slug identifying the candidate.|
|`support`|`uint8`|0=against, 1=for, 2=abstain (matches the DAO's voting enum)|
|`reason`|`string`|Free-text feedback emitted in the log.|


### sendProposalFeedback

Send on-chain feedback for an already-created formal proposal. Anyone can call;
intended for non-voters to register opinion or for voters to attach reasoning
outside the votes themselves.


```solidity
function sendProposalFeedback(uint256 proposalId, uint8 support, string calldata reason) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`proposalId`|`uint256`|The id of the formal proposal being commented on.|
|`support`|`uint8`|0=against, 1=for, 2=abstain (matches the DAO's voting enum).|
|`reason`|`string`|Free-text feedback emitted in the log.|


### _validateActions


```solidity
function _validateActions(
    address[] calldata targets,
    uint256[] calldata values,
    string[] calldata signatures,
    bytes[] calldata calldatas
) internal pure;
```

## Events
### ProposalCandidateCreated
Emitted when a pre-proposal candidate is created. The full body lives in the log.


```solidity
event ProposalCandidateCreated(
    address indexed proposer, bytes32 indexed slugHash, string slug, Candidate candidate, string reason
);
```

### ProposalCandidateUpdated
Emitted when a candidate is updated by its creator. The new body lives in the log.


```solidity
event ProposalCandidateUpdated(address indexed proposer, bytes32 indexed slugHash, CandidateUpdate update);
```

### ProposalCandidateCanceled
Emitted when a candidate is canceled by its creator, freeing the slug for re-use.


```solidity
event ProposalCandidateCanceled(address indexed proposer, bytes32 indexed slugHash);
```

### FeedbackSent
Emitted when a Shwoun holder posts on-chain support/feedback for a candidate.
Off-chain UIs can also accept signed feedback messages, but on-chain feedback
is the auditable canonical form.


```solidity
event FeedbackSent(
    address indexed sender,
    address indexed candidateProposer,
    bytes32 indexed candidateSlugHash,
    uint8 support,
    string reason
);
```

### ProposalFeedbackSent
Same as FeedbackSent but for already-created formal proposals.


```solidity
event ProposalFeedbackSent(address indexed sender, uint256 indexed proposalId, uint8 support, string reason);
```

## Errors
### CandidateAlreadyExists
Thrown when a (creator, slug) pair already has an active candidate.


```solidity
error CandidateAlreadyExists();
```

### CandidateNotFound
Thrown when updating/canceling/feedback-ing a (creator, slug) with no active candidate.


```solidity
error CandidateNotFound();
```

### InvalidSupportValue
Thrown when a feedback `support` value is greater than 2.


```solidity
error InvalidSupportValue();
```

### ActionsArrayLengthMismatch
Thrown when a candidate's targets/values/signatures/calldatas arrays differ in length.


```solidity
error ActionsArrayLengthMismatch();
```

### InvalidProposalActions
Thrown when a candidate has zero actions or more than 10.


```solidity
error InvalidProposalActions();
```

## Structs
### Candidate

```solidity
struct Candidate {
    address[] targets;
    uint256[] values;
    string[] signatures;
    bytes[] calldatas;
    string description;
}
```

### CandidateUpdate
Bundling event payload into a struct to reduce stack pressure on the emit site.


```solidity
struct CandidateUpdate {
    address[] targets;
    uint256[] values;
    string[] signatures;
    bytes[] calldatas;
    string description;
    string updateMessage;
}
```

