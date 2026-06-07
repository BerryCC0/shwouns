# IAuthRegistryLike
[Git Source](https://github.com/BerryCC0/shwouns/blob/c3d3c49ecaba298c2a599310448a09b917927b54/src/governance/Bootstrap.sol)

Minimal GovernanceAuthRegistry surface used by the immutable check + handoff bind.


## Functions
### binder

The immutable binder. @return The binder address.


```solidity
function binder() external view returns (address);
```

### daoLogic

The bound DAOLogic. @return The DAOLogic address (zero until bound).


```solidity
function daoLogic() external view returns (address);
```

### bindDAOLogic

Bind the DAOLogic proxy (called during finalize). @param daoLogic The DAOLogic to bind.


```solidity
function bindDAOLogic(address daoLogic) external;
```

