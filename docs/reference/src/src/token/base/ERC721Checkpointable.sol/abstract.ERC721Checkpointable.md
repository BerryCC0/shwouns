# ERC721Checkpointable
[Git Source](https://github.com/BerryCC0/shwouns/blob/c3d3c49ecaba298c2a599310448a09b917927b54/src/token/base/ERC721Checkpointable.sol)

**Inherits:**
[ERC721Enumerable](/src/token/base/ERC721Enumerable.sol/abstract.ERC721Enumerable.md)

**Title:**
Vote checkpointing for an ERC-721 token
░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ *
░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ *
░░░░░░█████████░░█████████░░░ *
░░░░░░██░░░████░░██░░░████░░░ *
░░██████░░░████████░░░████░░░ *
░░██░░██░░░████░░██░░░████░░░ *
░░██░░██░░░████░░██░░░████░░░ *
░░░░░░█████████░░█████████░░░ *
░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ *
░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ *


## Constants
### decimals
Defines decimals as per ERC-20 convention to make integrations with 3rd party governance platforms easier


```solidity
uint8 public constant decimals = 0
```


### DOMAIN_TYPEHASH
The EIP-712 typehash for the contract's domain


```solidity
bytes32 public constant DOMAIN_TYPEHASH =
    keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)")
```


### DELEGATION_TYPEHASH
The EIP-712 typehash for the delegation struct used by the contract


```solidity
bytes32 public constant DELEGATION_TYPEHASH =
    keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)")
```


## State Variables
### _delegates
A record of each accounts delegate


```solidity
mapping(address => address) private _delegates
```


### checkpoints
A record of votes checkpoints for each account, by index


```solidity
mapping(address => mapping(uint32 => Checkpoint)) public checkpoints
```


### numCheckpoints
The number of checkpoints for each account


```solidity
mapping(address => uint32) public numCheckpoints
```


### nonces
A record of states for signing / validating signatures


```solidity
mapping(address => uint256) public nonces
```


## Functions
### votesToDelegate

The votes a delegator can delegate, which is the current balance of the delegator.

Used when calling `_delegate()`


```solidity
function votesToDelegate(address delegator) public view returns (uint96);
```

### delegates

Overrides the standard `Comp.sol` delegates mapping to return
the delegator's own address if they haven't delegated.
This avoids having to delegate to oneself.


```solidity
function delegates(address delegator) public view returns (address);
```

### _beforeTokenTransfer

Adapted from `_transferTokens()` in `Comp.sol` to update delegate votes.

hooks into OpenZeppelin's `ERC721._transfer`


```solidity
function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal override;
```

### delegate

Delegate votes from `msg.sender` to `delegatee`


```solidity
function delegate(address delegatee) public;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`delegatee`|`address`|The address to delegate votes to|


### delegateBySig

Delegates votes from signatory to `delegatee`


```solidity
function delegateBySig(address delegatee, uint256 nonce, uint256 expiry, uint8 v, bytes32 r, bytes32 s) public;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`delegatee`|`address`|The address to delegate votes to|
|`nonce`|`uint256`|The contract state required to match the signature|
|`expiry`|`uint256`|The time at which to expire the signature|
|`v`|`uint8`|The recovery byte of the signature|
|`r`|`bytes32`|Half of the ECDSA signature pair|
|`s`|`bytes32`|Half of the ECDSA signature pair|


### getCurrentVotes

Gets the current votes balance for `account`


```solidity
function getCurrentVotes(address account) external view returns (uint96);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`account`|`address`|The address to get votes balance|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint96`|The number of current votes for `account`|


### getPriorVotes

Determine the prior number of votes for an account as of a block number

Block number must be a finalized block or else this function will revert to prevent misinformation.


```solidity
function getPriorVotes(address account, uint256 blockNumber) public view returns (uint96);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`account`|`address`|The address of the account to check|
|`blockNumber`|`uint256`|The block number to get the vote balance at|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint96`|The number of votes the account had as of the given block|


### _delegate


```solidity
function _delegate(address delegator, address delegatee) internal;
```

### _moveDelegates


```solidity
function _moveDelegates(address srcRep, address dstRep, uint96 amount) internal;
```

### _writeCheckpoint


```solidity
function _writeCheckpoint(address delegatee, uint32 nCheckpoints, uint96 oldVotes, uint96 newVotes) internal;
```

### safe32


```solidity
function safe32(uint256 n, string memory errorMessage) internal pure returns (uint32);
```

### safe96


```solidity
function safe96(uint256 n, string memory errorMessage) internal pure returns (uint96);
```

### add96


```solidity
function add96(uint96 a, uint96 b, string memory errorMessage) internal pure returns (uint96);
```

### sub96


```solidity
function sub96(uint96 a, uint96 b, string memory errorMessage) internal pure returns (uint96);
```

### getChainId


```solidity
function getChainId() internal view returns (uint256);
```

## Events
### DelegateChanged
An event thats emitted when an account changes its delegate


```solidity
event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);
```

### DelegateVotesChanged
An event thats emitted when a delegate account's vote balance changes


```solidity
event DelegateVotesChanged(address indexed delegate, uint256 previousBalance, uint256 newBalance);
```

## Structs
### Checkpoint
A checkpoint for marking number of votes from a given block


```solidity
struct Checkpoint {
    uint32 fromBlock;
    uint96 votes;
}
```

