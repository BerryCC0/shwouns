# IShwounsTokenLike
[Git Source](https://github.com/BerryCC0/shwouns/blob/c3d3c49ecaba298c2a599310448a09b917927b54/src/governance/ShwounsDAOInterfaces.sol)

**Title:**
Shwouns DAO Governance interfaces, types, and events

Forked from NounsDAOInterfaces.sol. Changes:
- Strip fork-related types (INounsDAOForkEscrow, IForkDAODeployer, fork events)
- Strip INounsDAOExecutor / timelock types (snapshot+collect+finalize replaces timelock)
- Strip NounsTokenLike (use IShwounsToken directly)
- Add SnapshotState struct for snapshot/collect bookkeeping per proposal
- Add Snapshotted + Collected to ProposalState enum
- Add ShwounsDAOParams and Storage adjustments matching our model
Original Copyright Compound Labs (BSD-3-Clause), modified by Nounders DAO, modified for Shwouns.

Subset of ShwounsToken used by the governance contracts. Avoids forcing
the concrete ShwounsToken to override base-class implementations of
totalSupply / getPriorVotes / getCurrentVotes (which are inherited from
ERC721Enumerable and ERC721Checkpointable).


## Functions
### totalSupply

The total Shwoun supply (the basis for BPS thresholds/quorum).


```solidity
function totalSupply() external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The total supply.|


### getCurrentVotes

The current voting weight of an account.


```solidity
function getCurrentVotes(address account) external view returns (uint96);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`account`|`address`|The account to query.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint96`|The current votes.|


### getPriorVotes

The voting weight of an account at a past block (Compound-style checkpoints).


```solidity
function getPriorVotes(address account, uint256 blockNumber) external view returns (uint96);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`account`|`address`|The account to query.|
|`blockNumber`|`uint256`|The historical block.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint96`|The votes at that block.|


### ownerOf

The owner of a Shwoun.


```solidity
function ownerOf(uint256 tokenId) external view returns (address);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tokenId`|`uint256`|The Shwoun id.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|The owner address.|


