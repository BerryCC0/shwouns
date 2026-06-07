# Signatory
[Git Source](https://github.com/BerryCC0/shwouns/blob/c3d3c49ecaba298c2a599310448a09b917927b54/src/vault/abstract/Signatory.sol)

**Inherits:**
IERC1271

**Title:**
Signatory

Implements ERC-1271 signature verification


## Functions
### isValidSignature

See [IERC1721-isValidSignature](/lib/openzeppelin-contracts/contracts/interfaces/IERC1271.sol/interface.IERC1271.md#isvalidsignature)


```solidity
function isValidSignature(bytes32 hash, bytes calldata signature) external view returns (bytes4 magicValue);
```

### _isValidSignature


```solidity
function _isValidSignature(bytes32 hash, bytes calldata signature) internal view virtual returns (bool);
```

