# ProposalEscrow
[Git Source](https://github.com/BerryCC0/shwouns/blob/c3d3c49ecaba298c2a599310448a09b917927b54/src/governance/ProposalEscrow.sol)

**Inherits:**
ERC721Holder, ERC1155Holder


## Constants
### daoLogic
The Shwouns DAOLogic proxy — the ONLY address permitted to drive this escrow.
The proxy address is upgrade-stable, so DAOLogic upgrades never change it.


```solidity
address public immutable daoLogic
```


### residualSink
The immutable residual sink (GovernanceRewards). Stray residuals recovered via the
terminal-gated rescue path (added in §A8) go here and nowhere else.


```solidity
address public immutable residualSink
```


## Functions
### constructor


```solidity
constructor(address _daoLogic, address _residualSink) ;
```

### onlyDAOLogic


```solidity
modifier onlyDAOLogic() ;
```

### receive

Accept ETH: from `collect`/`topUp` routing, from swap change, or from funds an
action returns to the escrow during execution.


```solidity
receive() external payable;
```

### execute

Execute the proposal's actions from this escrow's own identity and balance.
Callable only by DAOLogic, which sets its global execution lock + `activeProposalId`
(→ the transient `Executing` status) BEFORE calling, and clears them AFTER this
returns. Bubbles the first failing action's revert data — DAOLogic must NOT catch it
— so a failed action atomically rolls back the whole attempt and finalize stays
retryable.


```solidity
function execute(address[] calldata targets, uint256[] calldata values, bytes[] calldata calldatas)
    external
    onlyDAOLogic;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`targets`|`address[]`|The action target addresses (one per action).|
|`values`|`uint256[]`|The ETH value sent with each action (drawn from this escrow's balance).|
|`calldatas`|`bytes[]`|The calldata for each action.|


### payOut

Pay a specific asset/amount to a recipient. Used ONLY by DAOLogic's contribution
refund path; the recipient is derived by DAOLogic from the vault registry
(`vaultOf(shwounId)` — the contributing vault, whose receive() never reverts), never
caller-supplied. Use `address(0)` for native ETH.

A plain constrained transfer — never an arbitrary call, and it never touches DAOLogic's
executor authentication.


```solidity
function payOut(address asset, address to, uint256 amount) external onlyDAOLogic;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`asset`|`address`|The asset to transfer; `address(0)` for native ETH.|
|`to`|`address`|The recipient (the contributing vault, supplied by DAOLogic).|
|`amount`|`uint256`|The amount to transfer; a zero amount is a no-op.|


### sweepETHToSink

Sweep this escrow's entire ETH balance to the residual sink. No-op if zero.


```solidity
function sweepETHToSink() external onlyDAOLogic;
```

### sweepERC20ToSink

Sweep this escrow's entire balance of an ERC-20 to the residual sink. No-op if zero.


```solidity
function sweepERC20ToSink(address token) external onlyDAOLogic;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|The ERC-20 to sweep.|


### sweepERC721ToSink

Sweep one ERC-721 held by this escrow to the residual sink.


```solidity
function sweepERC721ToSink(address token, uint256 tokenId) external onlyDAOLogic;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|The ERC-721 collection.|
|`tokenId`|`uint256`|The token id to sweep.|


### sweepERC1155ToSink

Sweep an ERC-1155 balance held by this escrow to the residual sink.


```solidity
function sweepERC1155ToSink(address token, uint256 id, uint256 amount) external onlyDAOLogic;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|The ERC-1155 collection.|
|`id`|`uint256`|The token id.|
|`amount`|`uint256`|The amount to sweep.|


## Errors
### NotDAOLogic
Thrown when any entry point is called by an address other than `daoLogic`.


```solidity
error NotDAOLogic();
```

### LengthMismatch
Thrown when `execute` is given targets/values/calldatas arrays of unequal length.


```solidity
error LengthMismatch();
```

### ExecutionFailed
Thrown when action `index` reverts without bubbling revert data.


```solidity
error ExecutionFailed(uint256 index);
```

### ETHTransferFailed
Thrown when a native-ETH transfer (payOut / sweepETHToSink) fails.


```solidity
error ETHTransferFailed();
```

### ZeroAddress
Thrown when the constructor is given a zero `daoLogic` or `residualSink`.


```solidity
error ZeroAddress();
```

