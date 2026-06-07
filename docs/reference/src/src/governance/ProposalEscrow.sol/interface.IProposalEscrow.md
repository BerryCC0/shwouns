# IProposalEscrow
[Git Source](https://github.com/BerryCC0/shwouns/blob/c3d3c49ecaba298c2a599310448a09b917927b54/src/governance/ProposalEscrow.sol)

**Title:**
ProposalEscrow — per-proposal fund isolation + unique execution identity

One escrow per proposal. It holds ONLY that proposal's collected assets and executes
ALL of the proposal's actions (value-bearing AND governance) from its own unique
identity. Because the executing identity is unique per proposal, a lingering approval
or a stray output asset is reachable only by the proposal that produced it — closing
C-01 (reentrant double-spend across the shared pool) and C-02 (cross-proposal allowance
drain) by construction, rather than by balance bookkeeping in a shared arbitrary-call
wallet (which is not enforceable isolation).

The slim surface DAOLogic drives. Kept minimal so the library can call it without
importing the full contract.

Deployed as an EIP-1167 minimal-proxy clone (OpenZeppelin `Clones`, CREATE2 salt =
proposalId) of a single non-upgradeable implementation. EIP-1167 clones take no
constructor arguments, so the implementation bakes `daoLogic` and `residualSink` as
immutables into its runtime; every clone delegatecalls in and reads those immutables. Two
consequences the security model relies on:
1. ALL clones share one identical runtime codehash — required by DAOLogic's
executor-authentication codehash check (constructor-immutable per-escrow instances
would each have a distinct codehash and break that check).
2. There is deliberately NO `initialize()` anywhere. An initializer on a deterministic
clone address would be a front-running/takeover surface (anyone could init it first).
The escrow never stores its own proposalId; identity is established by DAOLogic from
the CREATE2 address.
The escrow is a DUMB executor: every entry point requires `msg.sender == daoLogic` (the
DAOLogic proxy address, which is upgrade-stable). DAOLogic supplies the action list and is
the sole driver of execution, refunds, and residual recovery.


## Functions
### daoLogic

The DAOLogic proxy that is the sole driver of this escrow.


```solidity
function daoLogic() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|The DAOLogic proxy address (baked in as an immutable on the implementation).|


### residualSink

The immutable sink (GovernanceRewards) that residual sweeps send to.


```solidity
function residualSink() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|The residual-sink address.|


### execute

Execute the proposal's actions from this escrow's own identity and balance.


```solidity
function execute(address[] calldata targets, uint256[] calldata values, bytes[] calldata calldatas) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`targets`|`address[]`|The action target addresses.|
|`values`|`uint256[]`|The ETH value to send with each action.|
|`calldatas`|`bytes[]`|The calldata for each action.|


### payOut

Pay a constrained asset/amount to a recipient (used by DAOLogic's refund path).


```solidity
function payOut(address asset, address to, uint256 amount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`asset`|`address`|The asset to transfer; `address(0)` for native ETH.|
|`to`|`address`|The recipient (DAOLogic derives it from the contributing vault, never caller-supplied).|
|`amount`|`uint256`|The amount to transfer.|


### sweepETHToSink

Sweep the escrow's entire ETH balance to the immutable residual sink.


```solidity
function sweepETHToSink() external;
```

### sweepERC20ToSink

Sweep the escrow's entire balance of an ERC-20 to the residual sink.


```solidity
function sweepERC20ToSink(address token) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|The ERC-20 to sweep.|


### sweepERC721ToSink

Sweep one ERC-721 to the residual sink.


```solidity
function sweepERC721ToSink(address token, uint256 tokenId) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|The ERC-721 collection.|
|`tokenId`|`uint256`|The token id to sweep.|


### sweepERC1155ToSink

Sweep an ERC-1155 balance to the residual sink.


```solidity
function sweepERC1155ToSink(address token, uint256 id, uint256 amount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|The ERC-1155 collection.|
|`id`|`uint256`|The token id.|
|`amount`|`uint256`|The amount to sweep.|


