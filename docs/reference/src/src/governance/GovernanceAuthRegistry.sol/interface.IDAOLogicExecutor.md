# IDAOLogicExecutor
[Git Source](https://github.com/BerryCC0/shwouns/blob/c3d3c49ecaba298c2a599310448a09b917927b54/src/governance/GovernanceAuthRegistry.sol)

Minimal view of DAOLogic's canonical executor predicate (kept separate to avoid importing
the facade into every governed contract).


## Functions
### isActiveExecutor

DAOLogic's canonical executor predicate (the source of truth this registry forwards to).


```solidity
function isActiveExecutor(address candidate) external view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`candidate`|`address`|The address to test.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|True iff `candidate` is the escrow of the proposal currently under the execution lock.|


