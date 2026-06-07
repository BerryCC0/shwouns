# ApprovalRegistry
[Git Source](https://github.com/BerryCC0/shwouns/blob/c3d3c49ecaba298c2a599310448a09b917927b54/src/rewards/ApprovalRegistry.sol)

**Inherits:**
[GovernedOwnable](/src/governance/GovernedOwnable.sol/abstract.GovernedOwnable.md)

**Title:**
ApprovalRegistry — DAO-curated allowlist of GI NFT tokenIds eligible for voter incentives

The DAO (via governance proposal) approves or revokes specific GI NFT tokenIds.
When a voter claims a voter incentive, they pass the tokenId they want to claim with;
the registry verifies (a) the tokenId is approved AND (b) the caller owns it.
Tokenid-keyed approval (rather than address-keyed) means approvals follow the NFT.
If alice's approved tokenId 5 is transferred to bob, bob inherits the approval.
This is intentional — the DAO is approving a specific identity-bound asset, not an
address.


## Constants
### giNFT
The Governance Incentives NFT whose token ids this registry curates.


```solidity
IERC721 public immutable giNFT
```


## State Variables
### approvedTokenIds
Whether a given GI NFT token id is approved to earn voter incentives.


```solidity
mapping(uint256 => bool) public approvedTokenIds
```


## Functions
### constructor


```solidity
constructor(IERC721 _giNFT, address _governanceAuth) GovernedOwnable(_governanceAuth);
```

### approve

Approve a tokenId. Only callable by owner (typically the DAOLogic post-deploy).


```solidity
function approve(uint256 tokenId) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tokenId`|`uint256`|The GI NFT token id to approve.|


### approveMany

Approve multiple tokenIds in one call.


```solidity
function approveMany(uint256[] calldata tokenIds) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tokenIds`|`uint256[]`|The GI NFT token ids to approve (already-approved ids are skipped).|


### revoke

Revoke approval of a tokenId.


```solidity
function revoke(uint256 tokenId) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tokenId`|`uint256`|The GI NFT token id to revoke.|


### isEligible

Check whether `holder` is eligible to claim using `tokenId`.


```solidity
function isEligible(address holder, uint256 tokenId) external view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`holder`|`address`|The address claiming a voter incentive.|
|`tokenId`|`uint256`|The GI NFT token id being claimed with.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|True iff `tokenId` is approved AND currently owned by `holder`.|


## Events
### TokenIdApproved
Emitted when a token id is approved.


```solidity
event TokenIdApproved(uint256 indexed tokenId);
```

### TokenIdRevoked
Emitted when a token id's approval is revoked.


```solidity
event TokenIdRevoked(uint256 indexed tokenId);
```

## Errors
### AlreadyApproved
Thrown when approving a token id that is already approved.


```solidity
error AlreadyApproved();
```

### NotApproved
Thrown when revoking a token id that is not approved.


```solidity
error NotApproved();
```

### InvalidTokenId
Thrown when the constructor is given a zero GI NFT address.


```solidity
error InvalidTokenId();
```

