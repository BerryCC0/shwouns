# IDescriptorLike
[Git Source](https://github.com/BerryCC0/shwouns/blob/c3d3c49ecaba298c2a599310448a09b917927b54/src/governance/Bootstrap.sol)

Minimal ShwounsDescriptor surface used by the wiring/immutable checks.


## Functions
### art

The art contract. @return The art address.


```solidity
function art() external view returns (address);
```

### arePartsLocked

Whether art parts are locked. @return True if locked.


```solidity
function arePartsLocked() external view returns (bool);
```

