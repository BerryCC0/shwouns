# IGovernanceAuthRegistry
[Git Source](https://github.com/BerryCC0/shwouns/blob/c3d3c49ecaba298c2a599310448a09b917927b54/src/governance/GovernanceAuthRegistry.sol)

**Title:**
GovernanceAuthRegistry — fail-closed indirection for executor authentication

The single place every governed contract consults to learn whether a caller is the
currently-authenticated active proposal escrow. It exists so the governed contracts can
take an `immutable governanceAuth` reference at CONSTRUCTION even though the DAOLogic
proxy is deployed AFTER them: the registry is deployed FIRST (by the Bootstrap
coordinator, which is its immutable binder), referenced by every governed contract, and
bound to the DAOLogic proxy exactly once afterwards.

Authorization is the one thing that must NEVER fail open. The forward to DAOLogic is
therefore defensive: while unbound it returns false; once bound, a revert / short /
malformed / non-true return all resolve to false; only a well-formed boolean `true`
authorizes. The DAOLogic address, once bound, is permanent (no setter, no re-bind).


## Functions
### isActiveExecutor

Whether `candidate` is the currently-authenticated active proposal escrow.


```solidity
function isActiveExecutor(address candidate) external view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`candidate`|`address`|The address to test (typically `msg.sender` of a governed contract).|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|True only while `candidate` is the escrow of the proposal mid-finalize; false otherwise.|


### daoLogic

The bound DAOLogic proxy (the canonical DAO). Zero until bound, then permanent.


```solidity
function daoLogic() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|The DAOLogic proxy address, or `address(0)` if not yet bound.|


