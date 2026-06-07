# IRewardsLike
[Git Source](https://github.com/BerryCC0/shwouns/blob/c3d3c49ecaba298c2a599310448a09b917927b54/src/governance/Bootstrap.sol)

Minimal GovernanceRewards surface used by the wiring checks.


## Functions
### dao

The registered DAOLogic. @return The DAOLogic address.


```solidity
function dao() external view returns (address);
```

### approvalRegistry

The approval registry. @return The registry address.


```solidity
function approvalRegistry() external view returns (address);
```

### daoLocked

Whether the DAOLogic reference is locked. @return True if locked.


```solidity
function daoLocked() external view returns (bool);
```

### approvalRegistryLocked

Whether the approval registry is locked. @return True if locked.


```solidity
function approvalRegistryLocked() external view returns (bool);
```

