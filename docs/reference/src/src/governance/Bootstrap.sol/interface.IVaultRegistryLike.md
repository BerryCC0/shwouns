# IVaultRegistryLike
[Git Source](https://github.com/BerryCC0/shwouns/blob/c3d3c49ecaba298c2a599310448a09b917927b54/src/governance/Bootstrap.sol)

Minimal ShwounsVaultRegistry surface used by the wiring/immutable checks.


## Functions
### vaultImplementation

The vault implementation. @return The implementation address.


```solidity
function vaultImplementation() external view returns (address);
```

### vaultImplementationLocked

Whether the vault implementation is locked. @return True if locked.


```solidity
function vaultImplementationLocked() external view returns (bool);
```

### daoLogic

The registered DAOLogic. @return The DAOLogic address.


```solidity
function daoLogic() external view returns (address);
```

### daoLogicLocked

Whether the DAOLogic reference is locked. @return True if locked.


```solidity
function daoLogicLocked() external view returns (bool);
```

### shwounsToken

The bound Shwouns token. @return The token address.


```solidity
function shwounsToken() external view returns (address);
```

