# GovernanceAuthRegistry
[Git Source](https://github.com/BerryCC0/shwouns/blob/c3d3c49ecaba298c2a599310448a09b917927b54/src/governance/GovernanceAuthRegistry.sol)

**Inherits:**
[IGovernanceAuthRegistry](/src/governance/GovernanceAuthRegistry.sol/interface.IGovernanceAuthRegistry.md)


## Constants
### binder
The only address permitted to bind DAOLogic — the registry's deployer (the Bootstrap
coordinator in production; the deploy/test harness otherwise).


```solidity
address public immutable binder
```


## State Variables
### daoLogic
The bound DAOLogic proxy (the canonical DAO). Zero until bound, then permanent.


```solidity
address public daoLogic
```


## Functions
### constructor


```solidity
constructor() ;
```

### bindDAOLogic

Bind the DAOLogic proxy. Only the binder, exactly once, to a nonzero DEPLOYED proxy.


```solidity
function bindDAOLogic(address _daoLogic) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_daoLogic`|`address`|The canonical DAOLogic proxy address to bind permanently.|


### isActiveExecutor

Fail-closed forward to DAOLogic's transient executor state.


```solidity
function isActiveExecutor(address candidate) external view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`candidate`|`address`|The address to test (typically the `msg.sender` of a governed contract).|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|True only if DAOLogic is bound AND returns a canonical boolean `true` for `candidate`; a revert, short return, malformed length, or non-`true` value all resolve to false.|


## Events
### DAOLogicBound
Emitted once, when the DAOLogic proxy is permanently bound.


```solidity
event DAOLogicBound(address indexed daoLogic);
```

## Errors
### NotBinder
Thrown when a non-binder calls `bindDAOLogic`.


```solidity
error NotBinder();
```

### AlreadyBound
Thrown when `bindDAOLogic` is called after DAOLogic has already been bound.


```solidity
error AlreadyBound();
```

### NotDeployed
Thrown when the bind target is the zero address or has no deployed code.


```solidity
error NotDeployed();
```

