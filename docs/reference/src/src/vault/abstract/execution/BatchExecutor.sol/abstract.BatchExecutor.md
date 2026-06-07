# BatchExecutor
[Git Source](https://github.com/BerryCC0/shwouns/blob/c3d3c49ecaba298c2a599310448a09b917927b54/src/vault/abstract/execution/BatchExecutor.sol)

**Inherits:**
[BaseExecutor](/src/vault/abstract/execution/BaseExecutor.sol/abstract.BaseExecutor.md)

**Title:**
Batch Executor

Allows multiple operations to be executed from this account in a single transaction


## Functions
### executeBatch

Executes a batch of operations if the caller is authorized


```solidity
function executeBatch(Operation[] calldata operations) external payable returns (bytes[] memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`operations`|`Operation[]`|Operations to execute|


## Structs
### Operation

```solidity
struct Operation {
    address to;
    uint256 value;
    bytes data;
    uint8 operation;
}
```

