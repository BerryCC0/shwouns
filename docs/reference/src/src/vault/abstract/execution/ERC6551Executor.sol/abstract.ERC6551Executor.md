# ERC6551Executor
[Git Source](https://github.com/BerryCC0/shwouns/blob/c3d3c49ecaba298c2a599310448a09b917927b54/src/vault/abstract/execution/ERC6551Executor.sol)

**Inherits:**
[IERC6551Executable](/src/vault/erc6551/interfaces/IERC6551Executable.sol/interface.IERC6551Executable.md), ERC165, [BaseExecutor](/src/vault/abstract/execution/BaseExecutor.sol/abstract.BaseExecutor.md)

**Title:**
ERC-6551 Executor

Basic executor which implements the IERC6551Executable execution interface


## Functions
### execute

Executes a low-level operation from this account if the caller is a valid executor


```solidity
function execute(address to, uint256 value, bytes calldata data, uint8 operation)
    external
    payable
    virtual
    returns (bytes memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`to`|`address`|Account to operate on|
|`value`|`uint256`|Value to send with operation|
|`data`|`bytes`|Encoded calldata of operation|
|`operation`|`uint8`|Operation type (0=CALL, 1=DELEGATECALL, 2=CREATE, 3=CREATE2)|


### supportsInterface


```solidity
function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool);
```

