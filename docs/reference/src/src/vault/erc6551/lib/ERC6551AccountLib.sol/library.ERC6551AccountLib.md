# ERC6551AccountLib
[Git Source](https://github.com/BerryCC0/shwouns/blob/c3d3c49ecaba298c2a599310448a09b917927b54/src/vault/erc6551/lib/ERC6551AccountLib.sol)


## Functions
### computeAddress


```solidity
function computeAddress(
    address registry,
    address _implementation,
    bytes32 _salt,
    uint256 chainId,
    address tokenContract,
    uint256 tokenId
) internal pure returns (address);
```

### isERC6551Account


```solidity
function isERC6551Account(address account, address expectedImplementation, address registry)
    internal
    view
    returns (bool);
```

### implementation


```solidity
function implementation(address account) internal view returns (address _implementation);
```

### implementation


```solidity
function implementation() internal view returns (address _implementation);
```

### token


```solidity
function token(address account) internal view returns (uint256, address, uint256);
```

### token


```solidity
function token() internal view returns (uint256, address, uint256);
```

### salt


```solidity
function salt(address account) internal view returns (bytes32);
```

### salt


```solidity
function salt() internal view returns (bytes32);
```

### context


```solidity
function context(address account) internal view returns (bytes32, uint256, address, uint256);
```

### context


```solidity
function context() internal view returns (bytes32, uint256, address, uint256);
```

